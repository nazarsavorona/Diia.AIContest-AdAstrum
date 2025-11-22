"""
Photo Validation API - Main Application Entry Point
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn
import logging
from app.core import settings

from app.api.routes import router
from app import __version__
from app.utils.frame_debugger import frame_saver

# Set up logging
resolved_log_level = getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO)
logging.basicConfig(
    level=resolved_log_level,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title=settings.APP_NAME,
    description="API for validating ID/passport photos for Diia app",
    version=__version__,
    docs_url="/docs",
    redoc_url="/redoc"
)

# Configure CORS for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify the actual iOS app domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routes
app.include_router(router, prefix="/api/v1", tags=["validation"])


@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "name": "Photo Validation API",
        "version": __version__,
        "status": "running",
        "docs": "/docs",
        "health": "/api/v1/health"
    }


@app.on_event("startup")
async def startup_event():
    """Initialize resources on startup"""
    logger.info("Starting Photo Validation API...")
    logger.info(f"Version: {__version__}")
    logger.info("API documentation available at /docs")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup resources on shutdown"""
    logger.info("Shutting down Photo Validation API...")
    logger.info(f"Total frames saved during session: {frame_saver._frame_count}")


# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Handle uncaught exceptions"""
    logger.error(f"Unhandled exception: {str(exc)}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "status": "error",
            "message": "Internal server error",
            "detail": str(exc) if app.debug else "An unexpected error occurred"
        }
    )


if __name__ == "__main__":
    # Run the server
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,  # Enable auto-reload during development
        log_level="info"
    )
