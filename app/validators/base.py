"""
Base validator class
"""

from abc import ABC, abstractmethod
from typing import Dict, Any
import numpy as np
from app.core.errors import ValidationResult


class BaseValidator(ABC):
    """Abstract base class for all validators"""
    
    def __init__(self):
        self.name = self.__class__.__name__
    
    @abstractmethod
    def validate(self, image: np.ndarray, context: Dict[str, Any] = None) -> ValidationResult:
        """
        Validate the image
        
        Args:
            image: Input image as numpy array (BGR format)
            context: Optional context from previous validators
            
        Returns:
            ValidationResult with pass/fail status and errors
        """
        pass
    
    def _create_result(self, passed: bool = True, metadata: Dict = None) -> ValidationResult:
        """Helper to create a ValidationResult"""
        return ValidationResult(passed=passed, metadata=metadata or {})
