#!/usr/bin/env python3
"""
Test script for validating the deployed backend with FLUXSynID-processed dataset
This script processes all images from the FLUXSynID-processed folder and tests them against the API
"""

import base64
import requests
import json
import os
import time
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple
from collections import defaultdict
import csv

# Configuration
BASE_URL = "https://d28w3hxcjjqa9z.cloudfront.net/api/v1"
PROCESSED_DATA_DIR = "FLUXSynID-processed"
RESULTS_DIR = "test_results"
REQUEST_TIMEOUT = 30
DELAY_BETWEEN_REQUESTS = 0.01  # seconds to avoid overwhelming the API
SAVE_DETAILED_RESPONSES = True  # Save detailed server responses to file

# Image type suffixes
IMAGE_TYPES = {
    "_f_doc.jpg": "document",
    "_f_live_0_a_d1.jpg": "live_angled",
    "_f_live_0_e_d1.jpg": "live_eye_level",
    "_f_live_0_p_d1.jpg": "live_profile",
}


class APITester:
    def __init__(self, base_url: str, processed_dir: str):
        self.base_url = base_url
        self.processed_dir = Path(processed_dir)
        self.results_dir = Path(RESULTS_DIR)
        self.results_dir.mkdir(exist_ok=True)
        
        # Statistics
        self.stats = {
            "total_images": 0,
            "successful_requests": 0,
            "failed_requests": 0,
            "api_errors": 0,
            "by_image_type": defaultdict(lambda: {"total": 0, "passed": 0, "failed": 0}),
            "by_status": defaultdict(int),
            "issues_found": defaultdict(int),
            "total_processing_time": 0,  # Total time for all API requests
            "request_times": [],  # Individual request times for FPS calculation
        }
        
        # Results storage
        self.detailed_results = []
        
        # File for detailed responses
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.responses_file = self.results_dir / f"detailed_responses_{timestamp}.log"
        self.responses_log = open(self.responses_file, 'w', encoding='utf-8')
        
    def encode_image_to_base64(self, image_path: Path) -> str:
        """Read image and encode to base64"""
        with open(image_path, "rb") as img_file:
            return base64.b64encode(img_file.read()).decode('utf-8')
    
    def test_health(self) -> bool:
        """Test health endpoint"""
        url = f"{self.base_url}/health"
        print(f"\n{'='*60}")
        print(f"Testing Health Endpoint: {url}")
        print(f"{'='*60}")
        
        try:
            response = requests.get(url, timeout=10)
            print(f"Status Code: {response.status_code}")
            
            if response.status_code == 200:
                result = response.json()
                print(f"Response: {json.dumps(result, indent=2)}")
                print(f"✓ Health check passed!")
                return True
            else:
                print(f"✗ Health check failed: {response.text}")
                return False
        except Exception as e:
            print(f"✗ Health check error: {e}")
            return False
    
    def validate_image(self, image_path: Path, endpoint: str = "validate/photo", mode: str = "full") -> Tuple[Dict, float]:
        """Send validation request for a single image"""
        url = f"{self.base_url}/{endpoint}"
        
        try:
            # Encode image
            base64_image = self.encode_image_to_base64(image_path)
            
            # Prepare payload
            payload = {
                "image": base64_image
            }
            if mode:
                payload["mode"] = mode
            
            # Send request and measure time
            start_time = time.time()
            response = requests.post(url, json=payload, timeout=REQUEST_TIMEOUT)
            request_time = time.time() - start_time
            
            if response.status_code == 200:
                result = response.json()
                return {
                    "success": True,
                    "status_code": 200,
                    "data": result
                }, request_time
            else:
                return {
                    "success": False,
                    "status_code": response.status_code,
                    "error": response.text
                }, request_time
                
        except requests.exceptions.Timeout:
            return {
                "success": False,
                "status_code": 408,
                "error": "Request timeout"
            }, REQUEST_TIMEOUT
        except Exception as e:
            return {
                "success": False,
                "status_code": 500,
                "error": str(e)
            }, 0.0
    
    def get_image_type(self, filename: str) -> str:
        """Determine image type from filename"""
        for suffix, img_type in IMAGE_TYPES.items():
            if filename.endswith(suffix):
                return img_type
        return "unknown"
    
    def process_all_images(self):
        """Process all images in the dataset"""
        print(f"\n{'='*60}")
        print(f"Starting Dataset Processing")
        print(f"{'='*60}")
        print(f"Base URL: {self.base_url}")
        print(f"Data Directory: {self.processed_dir}")
        print(f"Results Directory: {self.results_dir}")
        
        # Get all person directories
        person_dirs = sorted([d for d in self.processed_dir.iterdir() if d.is_dir()])
        total_persons = len(person_dirs)
        
        print(f"\nFound {total_persons} person directories to process")
        
        start_time = time.time()
        
        for idx, person_dir in enumerate(person_dirs, 1):
            person_id = person_dir.name
            print(f"\n{'-'*60}")
            print(f"Processing person {idx}/{total_persons}: {person_id}")
            print(f"{'-'*60}")
            
            # Get all images for this person
            image_files = sorted(person_dir.glob("*.jpg"))
            
            for img_file in image_files:
                self.stats["total_images"] += 1
                image_type = self.get_image_type(img_file.name)
                
                print(f"\n  Testing: {img_file.name} (Type: {image_type})")
                
                # Test with validate/photo endpoint and measure time
                result, request_time = self.validate_image(img_file)
                
                # Update statistics
                self.stats["by_image_type"][image_type]["total"] += 1
                self.stats["request_times"].append(request_time)
                self.stats["total_processing_time"] += request_time
                
                # Write detailed response to file
                self.responses_log.write(f"\n{'='*80}\n")
                self.responses_log.write(f"Person: {person_id} | Image: {img_file.name} | Type: {image_type}\n")
                self.responses_log.write(f"Request Time: {request_time:.3f}s\n")
                self.responses_log.write(f"{'='*80}\n")
                
                if result["success"]:
                    self.stats["successful_requests"] += 1
                    data = result["data"]
                    status = data.get("status", "unknown")
                    issues = data.get("issues", [])
                    
                    self.stats["by_status"][status] += 1
                    
                    if status == "valid":
                        self.stats["by_image_type"][image_type]["passed"] += 1
                        print(f"    ✓ Status: {status} | Time: {request_time:.3f}s")
                    else:
                        self.stats["by_image_type"][image_type]["failed"] += 1
                        print(f"    ⚠ Status: {status} | Time: {request_time:.3f}s")
                        print(f"    Issues: {', '.join(issues) if issues else 'None'}")
                        
                        # Count issues
                        for issue in issues:
                            self.stats["issues_found"][issue] += 1
                    
                    # Write full server response to file
                    self.responses_log.write(f"Server Response:\n")
                    self.responses_log.write(json.dumps(data, indent=2, ensure_ascii=False))
                    self.responses_log.write(f"\n\n")
                    
                    # Store detailed result
                    self.detailed_results.append({
                        "person_id": person_id,
                        "image_file": img_file.name,
                        "image_type": image_type,
                        "status": status,
                        "issues": issues,
                        "request_time": request_time,
                        "api_response": data
                    })
                else:
                    self.stats["failed_requests"] += 1
                    self.stats["by_image_type"][image_type]["failed"] += 1
                    print(f"    ✗ Request failed: {result.get('error', 'Unknown error')} | Time: {request_time:.3f}s")
                    
                    # Write error to file
                    self.responses_log.write(f"Error Response:\n")
                    self.responses_log.write(f"Status Code: {result.get('status_code', 'N/A')}\n")
                    self.responses_log.write(f"Error: {result.get('error', 'Unknown error')}\n\n")
                    
                    # Store error result
                    self.detailed_results.append({
                        "person_id": person_id,
                        "image_file": img_file.name,
                        "image_type": image_type,
                        "status": "error",
                        "error": result.get("error", "Unknown error"),
                        "status_code": result.get("status_code", 500),
                        "request_time": request_time
                    })
                
                # Small delay to avoid overwhelming the API
                time.sleep(DELAY_BETWEEN_REQUESTS)
        
        elapsed_time = time.time() - start_time
        self.stats["elapsed_time"] = elapsed_time
        
        print(f"\n{'='*60}")
        print(f"Processing Complete!")
        print(f"{'='*60}")
    
    def print_summary(self):
        """Print summary statistics"""
        # Calculate FPS metrics
        total_processing_time = self.stats.get('total_processing_time', 0)
        successful_requests = self.stats['successful_requests']
        request_times = self.stats.get('request_times', [])
        
        avg_fps = successful_requests / total_processing_time if total_processing_time > 0 else 0
        avg_request_time = sum(request_times) / len(request_times) if request_times else 0
        min_request_time = min(request_times) if request_times else 0
        max_request_time = max(request_times) if request_times else 0
        
        print(f"\n{'='*60}")
        print(f"TEST SUMMARY")
        print(f"{'='*60}")
        print(f"\nOverall Statistics:")
        print(f"  Total Images Tested: {self.stats['total_images']}")
        print(f"  Successful Requests: {self.stats['successful_requests']}")
        print(f"  Failed Requests: {self.stats['failed_requests']}")
        print(f"  Total Elapsed Time: {self.stats.get('elapsed_time', 0):.2f} seconds")
        
        print(f"\nPerformance Metrics:")
        print(f"  Total Processing Time: {total_processing_time:.2f} seconds")
        print(f"  Average FPS: {avg_fps:.2f} images/second")
        print(f"  Average Request Time: {avg_request_time:.3f} seconds")
        print(f"  Min Request Time: {min_request_time:.3f} seconds")
        print(f"  Max Request Time: {max_request_time:.3f} seconds")
        print(f"  Throughput: {successful_requests / self.stats.get('elapsed_time', 1):.2f} images/second (including delays)")
        
        if self.stats['successful_requests'] > 0:
            print(f"\nValidation Status Distribution:")
            for status, count in sorted(self.stats['by_status'].items()):
                percentage = (count / self.stats['successful_requests']) * 100
                print(f"  {status}: {count} ({percentage:.1f}%)")
        
        print(f"\nResults by Image Type:")
        for img_type, data in sorted(self.stats['by_image_type'].items()):
            total = data['total']
            passed = data['passed']
            failed = data['failed']
            pass_rate = (passed / total * 100) if total > 0 else 0
            print(f"  {img_type}:")
            print(f"    Total: {total}")
            print(f"    Passed: {passed} ({pass_rate:.1f}%)")
            print(f"    Failed: {failed}")
        
        if self.stats['issues_found']:
            print(f"\nMost Common Issues:")
            sorted_issues = sorted(self.stats['issues_found'].items(), 
                                 key=lambda x: x[1], reverse=True)
            for issue, count in sorted_issues[:10]:
                percentage = (count / self.stats['successful_requests']) * 100
                print(f"  {issue}: {count} ({percentage:.1f}%)")
    
    def save_results(self):
        """Save detailed results to files"""
        # Close responses log file
        self.responses_log.close()
        print(f"\n✓ Detailed responses saved to: {self.responses_file}")
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Save JSON results
        json_file = self.results_dir / f"test_results_{timestamp}.json"
        with open(json_file, 'w') as f:
            json.dump({
                "stats": dict(self.stats),
                "detailed_results": self.detailed_results
            }, f, indent=2)
        print(f"\n✓ Detailed results saved to: {json_file}")
        
        # Save CSV summary
        csv_file = self.results_dir / f"test_summary_{timestamp}.csv"
        with open(csv_file, 'w', newline='') as f:
            if self.detailed_results:
                writer = csv.DictWriter(f, fieldnames=[
                    "person_id", "image_file", "image_type", "status", 
                    "issues", "error", "status_code"
                ])
                writer.writeheader()
                for result in self.detailed_results:
                    row = {
                        "person_id": result.get("person_id", ""),
                        "image_file": result.get("image_file", ""),
                        "image_type": result.get("image_type", ""),
                        "status": result.get("status", ""),
                        "issues": ", ".join(result.get("issues", [])) if "issues" in result else "",
                        "error": result.get("error", ""),
                        "status_code": result.get("status_code", "")
                    }
                    writer.writerow(row)
        print(f"✓ CSV summary saved to: {csv_file}")
        
        # Save statistics summary
        stats_file = self.results_dir / f"statistics_{timestamp}.txt"
        with open(stats_file, 'w') as f:
            # Calculate FPS metrics
            total_processing_time = self.stats.get('total_processing_time', 0)
            successful_requests = self.stats['successful_requests']
            request_times = self.stats.get('request_times', [])
            
            avg_fps = successful_requests / total_processing_time if total_processing_time > 0 else 0
            avg_request_time = sum(request_times) / len(request_times) if request_times else 0
            min_request_time = min(request_times) if request_times else 0
            max_request_time = max(request_times) if request_times else 0
            
            f.write("="*60 + "\n")
            f.write("TEST SUMMARY\n")
            f.write("="*60 + "\n\n")
            f.write(f"Overall Statistics:\n")
            f.write(f"  Total Images Tested: {self.stats['total_images']}\n")
            f.write(f"  Successful Requests: {self.stats['successful_requests']}\n")
            f.write(f"  Failed Requests: {self.stats['failed_requests']}\n")
            f.write(f"  Total Elapsed Time: {self.stats.get('elapsed_time', 0):.2f} seconds\n\n")
            
            f.write(f"Performance Metrics:\n")
            f.write(f"  Total Processing Time: {total_processing_time:.2f} seconds\n")
            f.write(f"  Average FPS: {avg_fps:.2f} images/second\n")
            f.write(f"  Average Request Time: {avg_request_time:.3f} seconds\n")
            f.write(f"  Min Request Time: {min_request_time:.3f} seconds\n")
            f.write(f"  Max Request Time: {max_request_time:.3f} seconds\n")
            f.write(f"  Throughput: {successful_requests / self.stats.get('elapsed_time', 1):.2f} images/second (including delays)\n\n")
            
            if self.stats['successful_requests'] > 0:
                f.write("Validation Status Distribution:\n")
                for status, count in sorted(self.stats['by_status'].items()):
                    percentage = (count / self.stats['successful_requests']) * 100
                    f.write(f"  {status}: {count} ({percentage:.1f}%)\n")
                f.write("\n")
            
            f.write("Results by Image Type:\n")
            for img_type, data in sorted(self.stats['by_image_type'].items()):
                total = data['total']
                passed = data['passed']
                failed = data['failed']
                pass_rate = (passed / total * 100) if total > 0 else 0
                f.write(f"  {img_type}:\n")
                f.write(f"    Total: {total}\n")
                f.write(f"    Passed: {passed} ({pass_rate:.1f}%)\n")
                f.write(f"    Failed: {failed}\n")
            f.write("\n")
            
            if self.stats['issues_found']:
                f.write("Most Common Issues:\n")
                sorted_issues = sorted(self.stats['issues_found'].items(), 
                                     key=lambda x: x[1], reverse=True)
                for issue, count in sorted_issues:
                    percentage = (count / self.stats['successful_requests']) * 100
                    f.write(f"  {issue}: {count} ({percentage:.1f}%)\n")
        
        print(f"✓ Statistics saved to: {stats_file}")


def main():
    """Main test execution"""
    print("="*60)
    print("FLUXSynID-Processed Dataset Backend Test")
    print("="*60)
    
    # Initialize tester
    tester = APITester(BASE_URL, PROCESSED_DATA_DIR)
    
    # Check if data directory exists
    if not tester.processed_dir.exists():
        print(f"\n✗ Error: Data directory not found: {PROCESSED_DATA_DIR}")
        print("Please ensure the FLUXSynID-processed folder exists in the current directory.")
        return
    
    # Test health endpoint first
    if not tester.test_health():
        print("\n⚠ Warning: Health check failed. Continuing anyway...")
        response = input("Continue with testing? (y/n): ")
        if response.lower() != 'y':
            print("Testing aborted.")
            return
    
    # Process all images
    try:
        tester.process_all_images()
    except KeyboardInterrupt:
        print("\n\n⚠ Testing interrupted by user")
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # Ensure the log file is closed
        if hasattr(tester, 'responses_log') and not tester.responses_log.closed:
            tester.responses_log.close()
    
    # Print and save results
    tester.print_summary()
    tester.save_results()
    
    print(f"\n{'='*60}")
    print("Testing Complete!")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
