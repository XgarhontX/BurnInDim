# BurnInDim
ReShade shader that dim static pixels.
## Function / Usage
Compares new frame with previous frame for static/unchanged pixels, gradually dimming it over time, reseting it if changed. <br>
Works best for FPS/TPS games, as static cameras create false positives.
- This creates a dynamic UI mask.
  - a bit messed up for changing text, and antialiased elements' outline can be missed
- Dimming uses multiplication, HDR compatible.
## ReShade
- https://reshade.me/
