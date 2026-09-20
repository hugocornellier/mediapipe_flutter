# Independent storage audit comparison

Launch means are the experimental units. Positive reduction means faster. Acceptance requires both repeated blocks to beat the larger of 3% and all observed consecutive baseline A/A differences, with each candidate launch beating both bookends. Percentiles describe correlated frames.

| Candidate | Case | Before / after ms | Reduction | Floor | Verdict |
| --- | --- | ---: | ---: | ---: | --- |
| m0 | 1080x1920/cpu/33ms/public_api | 22.302 / 22.783 | -2.15% | 89.88% | inconclusive |
| m1 | 1080x1920/cpu/33ms/public_api | 16.429 / 16.161 | 1.63% | 89.88% | inconclusive |
| m2 | 1080x1920/cpu/33ms/public_api | 14.313 / 22.299 | -55.80% | 89.88% | inconclusive |
| m3 | 1080x1920/cpu/33ms/public_api | 18.397 / 16.362 | 11.06% | 89.88% | inconclusive |
| m0 | 1080x1920/cpu/tight/public_api | 22.763 / 20.843 | 8.43% | 125.49% | inconclusive |
| m1 | 1080x1920/cpu/tight/public_api | 14.631 / 14.197 | 2.97% | 125.49% | inconclusive |
| m2 | 1080x1920/cpu/tight/public_api | 11.810 / 22.229 | -88.22% | 125.49% | inconclusive |
| m3 | 1080x1920/cpu/tight/public_api | 16.919 / 15.110 | 10.69% | 125.49% | inconclusive |
| m0 | 1080x1920/gpu/33ms/public_api | 16.105 / 15.188 | 5.69% | 42.87% | inconclusive |
| m1 | 1080x1920/gpu/33ms/public_api | 13.461 / 13.683 | -1.65% | 42.87% | inconclusive |
| m2 | 1080x1920/gpu/33ms/public_api | 13.292 / 15.098 | -13.59% | 42.87% | inconclusive |
| m3 | 1080x1920/gpu/33ms/public_api | 14.345 / 14.233 | 0.78% | 42.87% | inconclusive |
| m0 | 1080x1920/gpu/tight/public_api | 13.616 / 12.560 | 7.75% | 79.54% | inconclusive |
| m1 | 1080x1920/gpu/tight/public_api | 9.754 / 9.787 | -0.33% | 79.54% | inconclusive |
| m2 | 1080x1920/gpu/tight/public_api | 8.503 / 12.695 | -49.31% | 79.54% | inconclusive |
| m3 | 1080x1920/gpu/tight/public_api | 10.308 / 8.364 | 18.86% | 79.54% | inconclusive |
| m0 | 480x640/cpu/33ms/public_api | 10.274 / 9.974 | 2.92% | 51.14% | inconclusive |
| m1 | 480x640/cpu/33ms/public_api | 9.458 / 8.957 | 5.29% | 51.14% | inconclusive |
| m2 | 480x640/cpu/33ms/public_api | 8.876 / 11.105 | -25.12% | 51.14% | inconclusive |
| m3 | 480x640/cpu/33ms/public_api | 10.438 / 8.918 | 14.56% | 51.14% | inconclusive |
| m0 | 480x640/cpu/tight/public_api | 12.793 / 14.066 | -9.95% | 127.34% | inconclusive |
| m1 | 480x640/cpu/tight/public_api | 8.210 / 7.955 | 3.11% | 127.34% | inconclusive |
| m2 | 480x640/cpu/tight/public_api | 6.488 / 12.594 | -94.11% | 127.34% | inconclusive |
| m3 | 480x640/cpu/tight/public_api | 9.432 / 8.884 | 5.80% | 127.34% | inconclusive |
| m0 | 480x640/gpu/33ms/public_api | 7.490 / 7.405 | 1.12% | 17.78% | inconclusive |
| m1 | 480x640/gpu/33ms/public_api | 8.062 / 7.878 | 2.28% | 17.78% | inconclusive |
| m2 | 480x640/gpu/33ms/public_api | 8.409 / 8.793 | -4.56% | 17.78% | inconclusive |
| m3 | 480x640/gpu/33ms/public_api | 9.085 / 8.326 | 8.35% | 17.78% | inconclusive |
| m0 | 480x640/gpu/tight/public_api | 7.002 / 7.381 | -5.40% | 117.59% | inconclusive |
| m1 | 480x640/gpu/tight/public_api | 4.485 / 4.484 | 0.02% | 117.59% | inconclusive |
| m2 | 480x640/gpu/tight/public_api | 3.417 / 5.765 | -68.71% | 117.59% | inconclusive |
| m3 | 480x640/gpu/tight/public_api | 4.453 / 4.801 | -7.80% | 117.59% | inconclusive |
