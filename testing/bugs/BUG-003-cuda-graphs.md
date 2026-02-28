# BUG-003 — CUDA graph decoder crashes on PyTorch nightly + RTX 5090

| Field | Value |
|-------|-------|
| **Status** | Closed — Workaround (disable CUDA graphs) |
| **Date found** | ~2026-01 |
| **Affected component** | `src/voice-transcribe-server`, `src/voice-transcribe-engine` |
| **Symptom** | `model.transcribe()` crashes or hangs |

## Symptom

```
RuntimeError: CUDA error: an illegal memory access was encountered
# or
Process hangs indefinitely on first transcription call
```

Occurs on first call to `model.transcribe()` after loading Parakeet TDT.

## Root Cause

Parakeet TDT enables `use_cuda_graph_decoder=True` by default. CUDA graph capture
requires a stable CUDA graph initialization sequence that PyTorch nightly cu128
does not yet support correctly for sm_120 (Blackwell — RTX 5090).

This is a known issue with early PyTorch support for new GPU architectures —
CUDA graph support lags behind general compute support by a few nightly builds.

## Fix

Disable CUDA graph decoder after loading the model, in both server and direct-load paths:

```python
from omegaconf import open_dict

with open_dict(model.cfg):
    model.cfg.decoding.greedy.use_cuda_graph_decoder = False
model.change_decoding_strategy(model.cfg.decoding)
```

This must be applied **before** the first `model.transcribe()` call.

## Performance Impact

Minimal. CUDA graphs provide a small latency reduction for repeated same-shape
calls. At ~0.2s per transcription (already extremely fast), disabling them has
no meaningful real-world impact.

## Expected Resolution

Once PyTorch stable releases full sm_120 support, this workaround can be removed.
Test by removing the `use_cuda_graph_decoder=False` block and checking for crashes.

## Files Changed

- `src/voice-transcribe-server`: added post-load config patch
- `src/voice-transcribe-engine`: added same patch in direct-load fallback
