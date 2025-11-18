"""
Pydantic models for API requests and responses
"""

from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from enum import Enum


class ValidationMode(str, Enum):
    """Validation mode"""
    FULL = "full"
    STREAM = "stream"


class ValidationRequest(BaseModel):
    """Request model for photo validation"""
    image: str = Field(..., description="Base64 encoded image data")
    mode: ValidationMode = Field(
        default=ValidationMode.FULL,
        description="Validation mode: 'full' for complete validation or 'stream' for real-time"
    )


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
