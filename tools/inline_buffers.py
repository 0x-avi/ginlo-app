"""Rewrite a .tflite so every weight buffer is stored inline (no offset/size external buffers).

Older LiteRT runtimes (e.g. the 1.4.0 bundled by tflite_flutter) ignore external buffers and
fail with "Input tensor N lacks data". Usage: python inline_buffers.py in.tflite out.tflite
"""
import sys
import numpy as np
import flatbuffers
try:
    from ai_edge_litert import schema_py_generated as S
except Exception:
    from tensorflow.lite.python import schema_py_generated as S

src, dst = sys.argv[1], sys.argv[2]
raw = open(src, "rb").read()
model = S.ModelT.InitFromObj(S.Model.GetRootAsModel(raw, 0))
moved = 0
for b in model.buffers:
    if b.offset and b.offset > 1:
        b.data = np.frombuffer(raw[b.offset:b.offset + b.size], dtype=np.uint8)
        b.offset, b.size = 0, 0
        moved += 1
builder = flatbuffers.Builder(len(raw) + 1024)
builder.Finish(model.Pack(builder), file_identifier=b"TFL3")
open(dst, "wb").write(builder.Output())
print(f"{src}: inlined {moved} buffers -> {dst}")
