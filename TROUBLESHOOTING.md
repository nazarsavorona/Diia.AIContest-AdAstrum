# Troubleshooting Guide

## Common Base64 Issues

### Issue: "Invalid base64 encoding: Non-base64 digit found"

**Cause**: The base64 string contains characters that aren't valid base64 (A-Z, a-z, 0-9, +, /, =)

**Solutions**:

1. **Check your encoding process**:
   ```python
   # ✅ CORRECT
   import base64
   with open('photo.jpg', 'rb') as f:
       base64_string = base64.b64encode(f.read()).decode('utf-8')
   
   # ❌ WRONG - Don't convert bytes to string first
   with open('photo.jpg', 'r') as f:
       base64_string = base64.b64encode(f.read()).decode('utf-8')
   ```

2. **Check for extra characters**:
   - Remove quotes if you're copying from JSON
   - Remove data URI prefix if present (the API handles this automatically)
   - Ensure no HTML tags or formatting

3. **Use the debug endpoint**:
   ```bash
   curl -X POST http://localhost:8000/api/v1/debug/base64 \
     -H "Content-Type: application/json" \
     -d '{"image": "YOUR_BASE64_HERE"}'
   ```

### Issue: "Cannot identify image file"

**Cause**: The decoded data is not a valid JPEG or PNG image

**Solutions**:

1. **Verify the source file**:
   ```bash
   file your_photo.jpg  # Should say "JPEG image data"
   ```

2. **Check file signature**:
   - JPEG files start with: `FF D8 FF`
   - PNG files start with: `89 50 4E 47`
   
   The debug endpoint will show you the file signature.

3. **Try re-encoding the image**:
   ```python
   from PIL import Image
   
   # Open and re-save as JPEG
   img = Image.open('photo.jpg')
   img.save('photo_fixed.jpg', 'JPEG', quality=95)
   ```

### Issue: "Base64 string is empty"

**Cause**: Empty or whitespace-only string sent

**Solution**: Verify you're reading the file correctly:
```python
# Check file exists and has content
import os
file_path = 'photo.jpg'
print(f"File exists: {os.path.exists(file_path)}")
print(f"File size: {os.path.getsize(file_path)} bytes")

# Read and encode
with open(file_path, 'rb') as f:
    data = f.read()
    print(f"Read {len(data)} bytes")
    base64_string = base64.b64encode(data).decode('utf-8')
    print(f"Base64 length: {len(base64_string)}")
```

## Working Examples

### Python Example
```python
import base64
import requests

# Method 1: Send base64
with open('photo.jpg', 'rb') as f:
    img_base64 = base64.b64encode(f.read()).decode('utf-8')

response = requests.post(
    'http://localhost:8000/api/v1/validate/photo',
    json={'image': img_base64, 'mode': 'full'}
)
print(response.json())

# Method 2: Upload file directly
with open('photo.jpg', 'rb') as f:
    response = requests.post(
        'http://localhost:8000/api/v1/validate/upload',
        files={'file': f}
    )
print(response.json())
```

### JavaScript Example
```javascript
// Browser - from file input
const fileInput = document.getElementById('photo-input');
const file = fileInput.files[0];

const reader = new FileReader();
reader.onload = async function(e) {
    const base64String = e.target.result.split(',')[1]; // Remove data URI prefix
    
    const response = await fetch('http://localhost:8000/api/v1/validate/photo', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
            image: base64String,
            mode: 'full'
        })
    });
    
    const result = await response.json();
    console.log(result);
};
reader.readAsDataURL(file);
```

### Swift/iOS Example
```swift
import Foundation

// Read image
guard let image = UIImage(named: "photo"),
      let imageData = image.jpegData(compressionQuality: 0.9) else {
    return
}

// Convert to base64
let base64String = imageData.base64EncodedString()

// Create request
var request = URLRequest(url: URL(string: "http://your-server:8000/api/v1/validate/photo")!)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

let body: [String: Any] = [
    "image": base64String,
    "mode": "full"
]
request.httpBody = try? JSONSerialization.data(withJSONObject: body)

// Send request
URLSession.shared.dataTask(with: request) { data, response, error in
    if let data = data,
       let result = try? JSONSerialization.jsonObject(with: data) {
        print(result)
    }
}.resume()
```

### cURL Example
```bash
# Create base64 from file
BASE64=$(base64 -i photo.jpg)

# Send request
curl -X POST http://localhost:8000/api/v1/validate/photo \
  -H "Content-Type: application/json" \
  -d "{\"image\": \"$BASE64\", \"mode\": \"full\"}"

# Or use file upload
curl -X POST http://localhost:8000/api/v1/validate/upload \
  -F "file=@photo.jpg"
```

## Debugging Steps

1. **Test health endpoint**:
   ```bash
   curl http://localhost:8000/api/v1/health
   ```

2. **Create a simple test image**:
   ```python
   python test_client.py
   ```

3. **Use the debug endpoint** to check your base64:
   ```python
   import requests
   
   response = requests.post(
       'http://localhost:8000/api/v1/debug/base64',
       json={'image': your_base64_string}
   )
   print(response.json())
   ```

4. **Check server logs** for detailed error messages

5. **Try file upload** instead of base64 if issues persist

## API Robustness Features

The API automatically handles:
- ✅ Missing base64 padding
- ✅ Data URI prefixes (data:image/jpeg;base64,...)
- ✅ URL-encoded base64 (- and _ characters)
- ✅ Extra whitespace and newlines
- ✅ Non-base64 characters (automatically stripped)
- ✅ Both standard and URL-safe base64

## Still Having Issues?

1. Use the `/debug/base64` endpoint to diagnose the problem
2. Try the `/validate/upload` endpoint with file upload instead
3. Check the example code above matches your implementation
4. Verify your image file is a valid JPEG or PNG
5. Check server logs for detailed error messages

## Performance Tips

- Use `mode: "stream"` for real-time camera feedback (faster)
- Use `mode: "full"` for final validation (more thorough)
- Compress images before sending (0.8-0.9 quality is fine)
- Keep images under 5MB for best performance
