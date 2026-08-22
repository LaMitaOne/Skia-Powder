Skia-Powder v0.1

RADStudio FMX / Skia4Delphi Powder Game Prototype "SkiaPowder"

A falling sand simulation (Powder Game) built entirely with Skia4Delphi. A classic cellular automata sandbox experience, featuring dynamic grid resolution, density-based fluid dynamics, reactive elements (fire, acid, lava), and an airbrush-style scattering system.
     
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/LaMitaOne/Skia-Powder)    
    
<img width="915" height="754" alt="Unbenannt" src="https://github.com/user-attachments/assets/13991a7a-4fc1-4952-bb5e-8363f29ae22d" />    

Sample Video: https://youtu.be/ZYbLVm2Xeu0     
         
🎮 Gameplay Features    
    
     Dynamic Grid Resolution: The simulation grid automatically resizes to fit any window dimensions on the fly, without destroying existing elements.
     Density-Based Physics: Materials interact based on weight. Sand sinks in water, oil floats on top of water, and gases rise to the ceiling.
     Cellular Automata Reactions: Complex chain reactions. Fire spreads to flammable materials, water extinguishes fire but turns into steam, lava melts sand/salt and slowly ignites wood, acid aggressively dissolves matter, and plants grow when touching water.
     Airbrush & Solid Brushing: Dynamic materials (liquids, powders, gases) are painted with a scattered airbrush effect for organic generation, while solids (walls, wood, ice) are drawn as continuous blocks.
     18 Unique Materials: Sand, Water, Wall, Wood, Fire, Powder, Nitro, Glitch (virus), Tap (cloner), Eraser, Oil, Lava, Steam, Acid, Salt, Plant, and Ice.

🕹️ Controls

     Draw/Interact: Left-Click & Drag
     Select Material: Use the UI Buttons on the left side of the screen      
      
🛠️ Technical Details

     Renderer: Pure Skia Canvas (No Game Engine, no FMX shapes). Every pixel is drawn directly and highly optimized using TSkPaint and DrawRect.
     Optimized Physics Loops: Solids, powders, and liquids are calculated bottom-to-top (gravity), while gases are calculated top-to-bottom (buoyancy). 
     Threading: Physics and reaction logic run on a background thread for consistent 60+ FPS, synchronized safely with the main rendering thread via TCriticalSection.
     Memory Management: Utilizes Delphi's dynamic 2D arrays (array of array of TCell) and SetLength to allow seamless grid resizing while preserving simulation state.
     State-Driven Architecture: Materials are defined by TMaterialState (Solid, Powder, Liquid, Gas) and Density, drastically reducing the code required for movement and collision logic.
    
🚀 Getting Started    
    
    Open the project in RAD Studio (Delphi).
    Ensure you have the Skia4Delphi library installed.
    Run and play!

Latest Changes:

v 0.1: Initial Release

     Implemented dynamic grid resolution that adapts to window size.
     Added 18 distinct materials with state-based movement (Powder, Liquid, Gas, Solid).
     Added density-based swapping (e.g., Sand sinks through Water).
     Implemented complex reactions (Fire spread, Lava melting Sand/Salt & slow ignition, Acid dissolution, Water->Steam evaporation, Plant growth, Glitch replication).
     Added UI toolbar with auto-generated material buttons.
     Added airbrush scattering for dynamic materials and solid brushing for structures.
     Fixed gas physics by separating the update loop (Top-Down pass) to prevent stacking artifacts.
     
License    
    
MIT License - Do whatever you want with it. Credits appreciated but not required. 

Happy sandboxing! 🏖️🔥     
     
More game repos:    
     
🎮 Skia4Delphi Games (each one file, no ext engine):    
   2D JumpnRun Platformer https://github.com/LaMitaOne/Skia_PlatformerGame   
   2D MegaCatling (Megaman platformer/shooter) https://github.com/LaMitaOne/Skia-MegaCatling     
   2D Lemmings/Worms/Portal/Touch hybrid https://github.com/LaMitaOne/SkiaLemmings       
   2D Side-scrolling space shooter https://github.com/LaMitaOne/SkiaStarPatrols    
   2D Tetris clone https://github.com/LaMitaOne/Skiatris     
   2D BombRunner (Bomberman clone) https://github.com/LaMitaOne/SkiaBombRunner     
   2.5D C&C style isometric rts https://github.com/LaMitaOne/Skia-RTS-Game   
   2.5D Isometric cat game https://github.com/LaMitaOne/Skia-A-Cats-Life    
   2.5D Raycasting doom base https://github.com/LaMitaOne/SkiaDoomBase    
   2.5D Voxel Raycasting Comanche https://github.com/LaMitaOne/Skia-Voxel-Comanche      
   3D better go to https://github.com/castle-engine     
     
🎮 Game components FMX:    
   MRX Gamepad Core https://github.com/LaMitaOne/MRX-Gamepad-Core    
