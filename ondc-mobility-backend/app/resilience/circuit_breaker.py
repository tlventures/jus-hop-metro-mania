import time
import pybreaker
from typing import Dict, Callable, Any
from app.core.config import settings
from app.core.logging import logger


class BppCircuitBreakerListener(pybreaker.CircuitBreakerListener):
    """
    Listener for recording circuit state transitions and logging metrics.
    """
    def state_change(self, cb, old_state, new_state):
        logger.warning(f"Circuit Breaker '{cb.name}' changed state from {old_state.name} to {new_state.name}")


# Global dictionary of circuit breakers keyed by BPP domain/URI
_circuit_breakers: Dict[str, pybreaker.CircuitBreaker] = {}


def get_bpp_circuit_breaker(bpp_id: str) -> pybreaker.CircuitBreaker:
    """
    Retrieves or creates a dedicated CircuitBreaker instance for a given Metro Seller (BPP) Node.
    """
    if bpp_id not in _circuit_breakers:
        cb = pybreaker.CircuitBreaker(
            fail_max=settings.CB_FAIL_MAX,
            reset_timeout=settings.CB_RESET_TIMEOUT,
            name=f"bpp_{bpp_id}",
            listeners=[BppCircuitBreakerListener()]
        )
        _circuit_breakers[bpp_id] = cb
    return _circuit_breakers[bpp_id]
