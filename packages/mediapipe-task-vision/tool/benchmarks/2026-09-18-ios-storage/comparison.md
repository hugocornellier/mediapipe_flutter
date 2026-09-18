# iOS face image-storage comparison

Positive reduction means faster. Two unchanged A/A launches establish a per-case noise floor, with a minimum acceptance threshold of 3%. An improvement also requires both candidate launch means to beat both bookending baseline means. Launch ranges and pooled percentiles are descriptive; no frame-level confidence intervals are claimed.

| Candidate | Case | Before / after mean ms | Reduction | Verdict |
| --- | --- | ---: | ---: | --- |
| FFI reuse | 1080x1920/cpu/33ms | 12.165 / 12.076 | 0.7% | inconclusive |
| Pixel pool | 1080x1920/cpu/33ms | 12.055 / 12.090 | -0.3% | inconclusive |
| Both | 1080x1920/cpu/33ms | 12.123 / 12.166 | -0.3% | inconclusive |
| FFI reuse | 1080x1920/cpu/tight | 9.900 / 9.781 | 1.2% | inconclusive |
| Pixel pool | 1080x1920/cpu/tight | 10.033 / 9.504 | 5.3% | improved |
| Both | 1080x1920/cpu/tight | 9.977 / 9.321 | 6.6% | improved |
| FFI reuse | 1080x1920/gpu/33ms | 18.640 / 18.329 | 1.7% | inconclusive |
| Pixel pool | 1080x1920/gpu/33ms | 18.414 / 18.316 | 0.5% | inconclusive |
| Both | 1080x1920/gpu/33ms | 18.319 / 18.309 | 0.1% | inconclusive |
| FFI reuse | 1080x1920/gpu/tight | 10.861 / 10.782 | 0.7% | inconclusive |
| Pixel pool | 1080x1920/gpu/tight | 10.885 / 10.407 | 4.4% | improved |
| Both | 1080x1920/gpu/tight | 10.899 / 10.293 | 5.6% | improved |
| FFI reuse | 480x640/cpu/33ms | 12.180 / 12.084 | 0.8% | inconclusive |
| Pixel pool | 480x640/cpu/33ms | 12.216 / 12.241 | -0.2% | inconclusive |
| Both | 480x640/cpu/33ms | 12.113 / 12.198 | -0.7% | inconclusive |
| FFI reuse | 480x640/cpu/tight | 7.059 / 7.065 | -0.1% | inconclusive |
| Pixel pool | 480x640/cpu/tight | 7.138 / 6.989 | 2.1% | inconclusive |
| Both | 480x640/cpu/tight | 7.109 / 6.926 | 2.6% | inconclusive |
| FFI reuse | 480x640/gpu/33ms | 16.503 / 16.749 | -1.5% | inconclusive |
| Pixel pool | 480x640/gpu/33ms | 16.831 / 16.840 | -0.1% | inconclusive |
| Both | 480x640/gpu/33ms | 16.601 / 16.252 | 2.1% | inconclusive |
| FFI reuse | 480x640/gpu/tight | 7.331 / 7.362 | -0.4% | inconclusive |
| Pixel pool | 480x640/gpu/tight | 7.130 / 6.946 | 2.6% | inconclusive |
| Both | 480x640/gpu/tight | 7.165 / 7.066 | 1.4% | inconclusive |
