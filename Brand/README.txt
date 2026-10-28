APRFree: the icon, the logo and the wordmark
============================================

Made October 6, 2026 from the design canvas, board "16 · App icon and logo · Direction A".
Every file here, and the app icon inside the project, is drawn by one script:

    swift Brand/make-brand.swift        (run it from the project folder)

Change the design in the script, run it, and every size is made again. Nothing here is edited by
hand. The same drawings exist as SwiftUI views for use inside the app: APRFree/Design/Logo.swift
(LogoMark, LogoWordmark, LogoLockup). A change to the design belongs in both.


1. THE APP ICON (IN THE PROJECT)
--------------------------------
APRFree/Assets.xcassets/AppIcon.appiconset, 48 images:

  Three looks       default (near-black ground), dark (black ground), tinted (greys; iOS lays the
                    user's tint colour over it)
  1024 x 1024       one for each look. Square, no rounded corners, no transparency. This is the
                    one the App Store shows, and all that Xcode strictly needs.
  Smaller sizes     20, 29, 38, 40, 60, 64, 68, 76 and 83.5 points at 2x and 3x, for each look

The smaller sizes are there because the board asks for it: "detail drops away as it shrinks".

  1024             everything: the stripes, the lit corner, "APRfree", the dot, the chip, the number
  60 to 83.5 pt    Home Screen: no lettering; a larger dot and chip
  38 and 40 pt     Spotlight: the three cards and the chip
  20 and 29 pt     Settings and notifications: the three cards alone

iOS rounds the corners itself. Never put rounded corners or transparency in these files.


2. FILES FOR EVERYWHERE ELSE (IN THIS FOLDER)
---------------------------------------------
icon/
  AppIcon-primary-1024.png   the default icon, square and opaque. Upload this where a store or a
                             form asks for "the app icon, 1024 x 1024".
  AppIcon-dark-1024.png      the dark look
  AppIcon-tinted-1024.png    the tinted look
  AppIcon-light-1024.png     the light look from the board. NOT used by the app: iOS has three
                             slots and the board has four looks. It is here if you want it as the
                             default instead, or as an alternate icon people can choose.
  icon-rounded-N.png         the default icon with its corners drawn in, on a clear ground, at
                             1024, 512, 256, 180, 120, 60, 40 and 29 pixels. For a website, a
                             document or a press page. Each is drawn for its size.

logo/
  lockup-light.png           the icon beside the wordmark, for LIGHT backgrounds (dark letters)
  lockup-dark.png            the same for DARK backgrounds (white letters)
  wordmark-light.png         the wordmark alone, for light backgrounds
  wordmark-dark.png          the wordmark alone, for dark backgrounds
  card-front.png             the front card of the icon at full size
                             Each also at @2x and @3x; the lockup and wordmark at @6x for print.
                             All have clear backgrounds.

svg/
  The same drawings as vector files, for any size: the icon in its four looks, the four small
  drawings, the wordmark, the lockup and the card. The lettering is saved as outlines, so they
  look the same on a computer that does not have the typeface.


3. THE COLOURS
--------------
  Ground            #1C1C1E   (dark look #000000, light look #F2F2F7)
  Back card         #2C2C2E   stripes #48484A
  Middle card       #0B2A5B   lit corner #1D4A8F
  Front card        #D9D9DE   (light look #FFFFFF with a #D1D1D6 edge)
  Lettering         #1C1C1E   (white on dark backgrounds)
  Dot and stroke    #34C759   (#30D158 on dark backgrounds)
  Chip              #C9A85C   lines #A88A45
  Number bars       #8E8E93 and #AEAEB2

The lettering is "APRfree", with a lower-case f, in the system typeface at its bold weight. The
app's name everywhere else stays "APRFree".


4. THINGS TO KNOW BEFORE USING THEM
-----------------------------------
- The wordmark is not placed anywhere in the app yet. You said you would say where. The icon is
  used in one place besides the Home Screen: the About row in Settings.
- The number and the name on the card are made up (the number does not pass a card-number check).
- The typeface is Apple's. Apple licenses it for apps on its own platforms. For a website or
  print, check Apple's font licence first or redraw the wordmark in a typeface you have a licence
  for. The script takes one line to change: the two places that say NSFont.systemFont.
- iOS 26 can also take a layered icon built in Apple's Icon Composer. The flat one here is
  accepted and is what the app uses. The three cards would make natural layers if you try it.
- Keep bank names and bank-coloured cards out of anything made for the App Store page
  (preparation.txt, section 2). The icon has neither.
