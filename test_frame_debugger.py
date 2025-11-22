"""
Test script to verify frame saver works and saves frames to disk.
"""
import numpy as np
import cv2
from pathlib import Path
from app.utils.frame_debugger import frame_saver


def test_frame_saver():
    """Test if frame saver can save frames to disk."""
    print(f"Frame saver enabled: {frame_saver.enabled}")
    print(f"Output directory: {frame_saver.output_dir}")
    print(f"Max frames: {frame_saver.max_frames}")

    if not frame_saver.enabled:
        print("\n⚠️  Frame saver is disabled!")
        print("This could be because DEBUG_SAVE_FRAMES is set to 'false' in .env")
        return

    # Clear existing frames for clean test
    print("\n🧹 Clearing existing frames...")
    cleared = frame_saver.clear_all_frames()
    print(f"✓ Cleared {cleared} existing frames")

    # Create a test success frame
    test_image = np.zeros((480, 640, 3), dtype=np.uint8)
    test_image[:] = (100, 150, 200)  # BGR color

    cv2.putText(
        test_image,
        "Test Success Frame",
        (50, 240),
        cv2.FONT_HERSHEY_SIMPLEX,
        1.0,
        (255, 255, 255),
        2,
        cv2.LINE_AA
    )

    print("\n📸 Saving success frame...")
    frame_saver.save(test_image, status="success", errors=None)

    # Create a test failure frame
    test_image[:] = (100, 100, 200)  # Different color
    cv2.putText(
        test_image,
        "Test Failure Frame",
        (50, 240),
        cv2.FONT_HERSHEY_SIMPLEX,
        1.0,
        (255, 255, 255),
        2,
        cv2.LINE_AA
    )

    print("📸 Saving failure frame...")
    frame_saver.save(
        test_image,
        status="fail",
        errors=[{"code": "FACE_NOT_FOUND"}, {"code": "QUALITY_TOO_LOW"}]
    )

    # Create a few more test frames
    print("📸 Saving additional test frames...")
    for i in range(3):
        test_image[:] = (50 + i*50, 100, 150)
        cv2.putText(
            test_image,
            f"Test Frame #{i+3}",
            (50, 240),
            cv2.FONT_HERSHEY_SIMPLEX,
            1.0,
            (255, 255, 255),
            2,
            cv2.LINE_AA
        )
        status = "success" if i % 2 == 0 else "fail"
        frame_saver.save(test_image, status=status, errors=None)

    # List saved frames
    saved_frames = sorted(frame_saver.output_dir.glob("frame_*.jpg"))
    print(f"\n✓ Frame saver is working!")
    print(f"✓ Total frames saved: {len(saved_frames)}")
    print(f"✓ Frames location: {frame_saver.output_dir.absolute()}")
    print("\n📁 Saved frames:")
    for frame_file in saved_frames:
        size_kb = frame_file.stat().st_size / 1024
        print(f"   - {frame_file.name} ({size_kb:.1f} KB)")

    print(f"\n💡 You can view the frames with:")
    print(f"   open {frame_saver.output_dir.absolute()}")


if __name__ == "__main__":
    test_frame_saver()

