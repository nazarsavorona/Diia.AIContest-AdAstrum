"""
Pydantic models for API requests and responses
"""

from pydantic import BaseModel, Field, model_validator
from typing import List, Optional, Dict, Any
from enum import Enum


class ValidationMode(str, Enum):
    """Validation mode"""
    FULL = "full"
    STREAM = "stream"


class ValidationRequest(BaseModel):
    """Request model for photo validation"""
    image: Optional[str] = Field(
        default=None,
        description="Base64 encoded image data (unencrypted)"
    )
    encrypted_image: Optional[str] = Field(
        default=None,
        description="AES-GCM encrypted base64 image payload (nonce+ciphertext+tag, base64 encoded)"
    )
    encryption: Optional[str] = Field(
        default=None,
        description="Encryption scheme for 'encrypted_image' (default: aes_gcm)"
    )
    mode: ValidationMode = Field(
        default=ValidationMode.FULL,
        description="Validation mode: 'full' for complete validation or 'stream' for real-time"
    )

    @model_validator(mode="after")
    def _require_image_payload(self):
        """Ensure at least one payload field is provided."""
        if not self.image and not self.encrypted_image:
            raise ValueError("Either 'image' or 'encrypted_image' must be provided")
        return self


class ErrorDetail(BaseModel):
    """Error detail model"""
    code: str = Field(..., description="Error code")
    message: str = Field(..., description="Human-readable error message")


class ValidationResponse(BaseModel):
    """Response model for photo validation"""
    status: str = Field(..., description="Validation status: 'success' or 'fail'")
    errors: List[ErrorDetail] = Field(default_factory=list, description="List of validation errors")
    metadata: Optional[Dict[str, Any]] = Field(default=None, description="Additional metadata from validation")


class StreamValidationResponse(BaseModel):
    """Response model for stream validation with guidance data"""
    status: str = Field(..., description="Validation status: 'success' or 'fail'")
    errors: List[ErrorDetail] = Field(default_factory=list, description="List of validation errors")
    landmarks: Optional[List[Dict[str, float]]] = Field(
        default=None,
        description="Face landmarks for UI overlay"
    )
    guidance: Optional[Dict[str, Any]] = Field(
        default=None,
        description="Real-time guidance data (pose, centering, etc.)"
    )


class HealthResponse(BaseModel):
    """Health check response"""
    status: str = Field(default="healthy", description="Service health status")
    version: str = Field(..., description="API version")
    models_loaded: bool = Field(..., description="Whether ML models are loaded")
