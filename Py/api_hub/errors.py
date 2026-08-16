# -*- coding: utf-8 -*-
"""
Custom exception hierarchy for the API Hub bindings.
"""

class ApiError(Exception):
    """Base exception for all API‑related errors."""
    pass

class ConnectionError(ApiError):
    """Raised when connecting to a remote service fails."""
    pass

class TimeoutError(ApiError):
    """Raised when a synchronous call times out."""
    pass

class RegistrationError(ApiError):
    """Raised when API registration fails (e.g., duplicate name)."""
    pass

class SerializationError(ApiError):
    """Raised when serialization or deserialization fails."""
    pass