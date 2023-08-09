# BurnInDim
ReShade shader that dim static pixels.
## Function / Usage
Compares new frame with previous frame for static/unchanged pixels, gradually dimming it over time, reseting it if changed. <br>
Works best for FPS/TPS games, as static cameras create false positives. <br>
- This creates a dynamic UI mask.
  - A bit messed up for changing text, and antialiased elements' outline can be missed
- Dimming uses multiplication, HDR compatible.
  - I made it for my OLED monitor, to maybe prevent burn in and reduce wasted bright pixels.
## ReShade
- https://reshade.me/
