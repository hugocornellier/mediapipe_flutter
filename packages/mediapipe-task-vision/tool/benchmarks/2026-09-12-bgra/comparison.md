# Face pipeline comparison

Positive reduction means faster. Means weight each round equally; percentiles pool frames and are descriptive, not confidence intervals. See JSON for individual round means and their ranges.

| Input / delegate | Before mean / p95 ms | After mean / p95 ms | Mean reduction |
| --- | ---: | ---: | ---: |
| 1280x720_bgra_pad64/cpu | 6.922 / 7.818 | 6.114 / 6.660 | 11.7% |
| 1280x720_bgra_pad64/gpu | 5.120 / 6.226 | 4.477 / 5.824 | 12.6% |
| 1920x1080_bgra_pad64/cpu | 9.381 / 10.483 | 7.706 / 8.693 | 17.8% |
| 1920x1080_bgra_pad64/gpu | 8.330 / 9.205 | 6.525 / 7.446 | 21.7% |
| 1920x1080_rgba_pad64/cpu | 6.175 / 7.144 | 5.929 / 6.365 | 4.0% |
| 1920x1080_rgba_pad64/gpu | 4.599 / 5.665 | 4.515 / 5.722 | 1.8% |
| 640x480_bgra_pad64/cpu | 5.622 / 6.365 | 5.252 / 5.889 | 6.6% |
| 640x480_bgra_pad64/gpu | 3.300 / 4.110 | 3.070 / 3.796 | 7.0% |
