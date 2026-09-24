"""Google's Python reads MpEmbeddingResult with the wrong layout; fix that.

Shared by the text reference generators, which run inside the official wheel.
"""
import ctypes


def use_header_embedding_layout():
    """Makes Google's Python read embedding results with the C header's layout.

    The wheel's ctypes declare MpEmbeddingResult as 24 bytes with the timestamp
    flag first. The library writes the header's 32 bytes (timestamp, then the
    flag), so Python overruns its allocation and reads the flag from padding,
    reporting no timestamp.
    """
    from mediapipe.tasks.python.components.containers import embedding_result_c as module
    old = module.MpEmbeddingResultC
    # A future wheel that fixes its ctypes makes this unnecessary; fail loudly.
    assert [name for name, _ in old._fields_] == [
        'embeddings', 'embeddings_count', 'has_timestamp_ms', 'timestamp_ms'], old._fields_

    class MpEmbeddingResultC(ctypes.Structure):
        _fields_ = [('embeddings', ctypes.POINTER(module.MpEmbeddingC)),
                    ('embeddings_count', ctypes.c_uint32),
                    ('timestamp_ms', ctypes.c_int64),
                    ('has_timestamp_ms', ctypes.c_bool)]
    module.MpEmbeddingResultC = MpEmbeddingResultC
    # `import mediapipe` already bound the old struct into the embedder's C
    # signatures; rebuild them.
    import importlib
    from mediapipe.tasks.python.text import text_embedder
    importlib.reload(text_embedder)
