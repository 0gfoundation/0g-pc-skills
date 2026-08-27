"""Workaround: 0G Router ends every stream with a billing chunk whose "choices" is [],
and LiteLLM's Responses-API bridge crashes on it (choices[0] IndexError).
Loaded via litellm_settings.callbacks; remove once fixed upstream in LiteLLM."""
from litellm.integrations.custom_logger import CustomLogger
from litellm.responses.litellm_completion_transformation import streaming_iterator as _si

_orig = _si.LiteLLMCompletionStreamingIterator._get_delta_string_from_streaming_choices

def _safe(self, choices):
    if not choices:
        return ""
    return _orig(self, choices)

_si.LiteLLMCompletionStreamingIterator._get_delta_string_from_streaming_choices = _safe

class _Noop(CustomLogger):
    pass

zg_patch_instance = _Noop()
