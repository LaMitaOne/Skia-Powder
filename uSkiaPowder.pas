{*******************************************************************************
  SkiaPowder
********************************************************************************
  A high-performance, GPU-rendered falling sand simulation (Powder Game)
  built on Skia4Delphi.

  Features:
  - Dynamic grid resolution that adapts to window size.
  - Realtime physics calculated in a background thread to keep UI smooth.
  - Cellular Automata reactions (Fire, Acid, Lava, Plant growth, etc.).
  - Density-based fluid dynamics (Oil floats on Water, Sand sinks).
  - Airbrush-style scattering for dynamic materials, solid brush for structures.
  - Color Blending: Liquids mix their colors at the edges for smooth gradients.
  - Shockwave System: Explosions create physical pressure that destroys walls
    and blasts away materials. Perfect for Volcano eruptions.
  - Separated Update Loops:
    * Bottom-to-Top pass for Gravity (Powders, Liquids).
    * Top-to-Bottom pass for Buoyancy (Gases, Fire, Steam).

  Author:  Lara Miriam Tamy Reschke
  License: MIT

  v 0.1

*******************************************************************************}
unit uSkiaPowder;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.Math, System.SyncObjs,
  FMX.Types, FMX.Controls, FMX.Skia, System.Skia, System.UITypes;

const
  TARGET_CELL_SIZE = 5; // Pixel size of a single grid cell. Smaller = finer sand.

type
  TMaterialType = (mtEmpty, mtSand, mtWater, mtWall, mtWood, mtFire, mtPowder, mtNitro, mtGlitch, mtTap, mtEraser, mtOil, mtLava, mtSteam, mtAcid, mtSalt, mtPlant, mtIce);

  TMaterialState = (msEmpty, msSolid, msPowder, msLiquid, msGas);

  // Represents a single pixel in the simulation
  TCell = record
    MatType: TMaterialType;
    Color: TAlphaColor;
    Life: Integer;          // Lifespan for Gases and Fire (ticks)
    Flammable: Integer;     // 0 = No, >0 = How easily it catches fire
    State: TMaterialState;  // Determines physics behavior
    Density: Integer;      // Determines what sinks or swims
    Updated: Boolean;       // Prevents multiple updates in a single frame
    SpawnType: TMaterialType; // Used for the Tap tool to remember what to clone
    Velocity: Integer;      // Explosion force / knockback
    Integrity: Integer;     // HP for solids (Walls) to resist explosions
  end;

  // Custom type for dynamic arrays to allow direct assignment
  TCellGrid = array of array of TCell;

  TSkiaPowder = class(TSkCustomControl)
  private
    FThread: TThread;
    FActive: Boolean;
    FLock: TCriticalSection;

    { Dynamic Grid }
    FGrid: TCellGrid;
    FGridW, FGridH: Integer;

    { Input & Tools }
    FSelectedMaterial: TMaterialType;
    FMouseX, FMouseY: Single;
    FIsMouseDown: Boolean;
    FBrushRadius: Integer;

    { Core Methods }
    procedure ResizeGrid;
    procedure DoPhysicsUpdate(DeltaSec: Double);
    procedure SafeInvalidate;
    procedure StartThread;
    procedure StopThread;

    { Grid Manipulation }
    function InBounds(X, Y: Integer): Boolean; inline;
    procedure SetCell(X, Y: Integer; MatType: TMaterialType);
    function GetCell(X, Y: Integer): TCell;
    procedure MoveCell(X1, Y1, X2, Y2: Integer);
    procedure SwapCells(X1, Y1, X2, Y2: Integer);
    procedure PaintAtMousePos;

    { Physics Helpers }
    procedure IgniteCell(X, Y: Integer);
    procedure Explode(X, Y, Radius, Force: Integer);
    procedure ApplyPressure(X, Y, Force: Integer);
    function BlendColors(C1, C2: TAlphaColor): TAlphaColor;
    procedure MixLiquidColors(X, Y: Integer; C: TCell);
    procedure MovePowder(X, Y: Integer; const C: TCell);
    procedure MoveLiquid(X, Y, Dir: Integer; const C: TCell);
    procedure MoveGas(X, Y, Dir: Integer; const C: TCell);
    procedure ProcessReactions(X, Y: Integer; var C: TCell);

    { Helpers }
    function GetCellWidth: Single;
    function GetCellHeight: Single;
    function PointToGrid(X, Y: Single): TPoint;

    { Rendering }
    procedure DrawGrid(const ACanvas: ISkCanvas);
  protected
    procedure Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetMaterialName(MatType: TMaterialType): string;
    property SelectedMaterial: TMaterialType read FSelectedMaterial write FSelectedMaterial;
  end;

implementation

{ TSkiaPowder }

constructor TSkiaPowder.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLock := TCriticalSection.Create;
  HitTest := True;
  CanFocus := True;
  FActive := True;
  FSelectedMaterial := mtSand;
  FBrushRadius := 2; // Fine, precise brush
  FGridW := 0;
  FGridH := 0;
  ResizeGrid; // Initialize grid based on initial size
  StartThread;
end;

destructor TSkiaPowder.Destroy;
begin
  StopThread;
  FreeAndNil(FLock);
  inherited;
end;

{ =============================================================================
  DYNAMIC GRID & RESIZING
  The grid is a 2D array of TCell. When the window resizes, we backup the old
  grid, create a new one with the new dimensions, and copy the overlapping data
  back to preserve the player's creations.
============================================================================= }
procedure TSkiaPowder.ResizeGrid;
var
  NewW, NewH, X, Y, CopyW, CopyH: Integer;
  OldGrid: TCellGrid;
begin
  NewW := Trunc(Self.Width / TARGET_CELL_SIZE);
  NewH := Trunc(Self.Height / TARGET_CELL_SIZE);
  if NewW < 10 then
    NewW := 10;
  if NewH < 10 then
    NewH := 10;

  if (NewW <> FGridW) or (NewH <> FGridH) then
  begin
    FLock.Acquire;
    try
      OldGrid := FGrid; // Backup current sand
      CopyW := Min(FGridW, NewW);
      CopyH := Min(FGridH, NewH);

      FGridW := NewW;
      FGridH := NewH;
      SetLength(FGrid, FGridW, FGridH);

      // Restore old data or init empty
      for X := 0 to FGridW - 1 do
      begin
        for Y := 0 to FGridH - 1 do
        begin
          if (X < CopyW) and (Y < CopyH) then
            FGrid[X, Y] := OldGrid[X, Y]
          else
          begin
            FGrid[X, Y] := Default(TCell);
            FGrid[X, Y].MatType := mtEmpty;
            FGrid[X, Y].State := msEmpty;
          end;
        end;
      end;
    finally
      FLock.Release;
    end;
  end;
end;

procedure TSkiaPowder.Resize;
begin
  inherited;
  ResizeGrid;
  Redraw;
end;

{ =============================================================================
  GRID LOGIC & SAFETY
  Safe accessors and low-level cell manipulators. Moving a cell means we copy
  its entire data struct to the new position and reset the old position to Empty.
============================================================================= }
function TSkiaPowder.InBounds(X, Y: Integer): Boolean;
begin
  Result := (X >= 0) and (X < FGridW) and (Y >= 0) and (Y < FGridH);
end;

procedure TSkiaPowder.SetCell(X, Y: Integer; MatType: TMaterialType);
begin
  if not InBounds(X, Y) then
    Exit;

  if MatType = mtEraser then
  begin
    FGrid[X, Y] := Default(TCell);
    FGrid[X, Y].MatType := mtEmpty;
    FGrid[X, Y].State := msEmpty;
    Exit;
  end;

  // Don't overwrite if it's the same material (except for Fire, which we might want to refresh)
  if (FGrid[X, Y].MatType = MatType) and (MatType <> mtFire) then
    Exit;
  // Solids can only be destroyed by explosions or acid, not painted over
  if (FGrid[X, Y].State = msSolid) and (MatType <> mtFire) then
    Exit;

  FGrid[X, Y].MatType := MatType;
  FGrid[X, Y].Updated := True;
  FGrid[X, Y].Flammable := 0;
  FGrid[X, Y].SpawnType := mtTap;
  FGrid[X, Y].Life := 0;
  FGrid[X, Y].Velocity := 0;
  FGrid[X, Y].Integrity := 0;

  // Initialize physical properties based on material type
  case MatType of
    mtSand:
      begin
        FGrid[X, Y].Color := $FFEDD583; // Bright yellow sand
        FGrid[X, Y].State := msPowder;
        FGrid[X, Y].Density := 50;
        FGrid[X, Y].Flammable := 0;    // Sand doesn't burn
      end;
    mtWater:
      begin
        FGrid[X, Y].Color := $FF4080FF;
        FGrid[X, Y].State := msLiquid;
        FGrid[X, Y].Density := 40;
      end;
    mtWall:
      begin
        FGrid[X, Y].Color := $FF808080; // Gray stone
        FGrid[X, Y].State := msSolid;
        FGrid[X, Y].Density := 100;
        FGrid[X, Y].Integrity := 100;   // High HP against blasts
      end;
    mtWood:
      begin
        FGrid[X, Y].Color := $FF4A2C1A; // Dark brown wood
        FGrid[X, Y].State := msSolid;
        FGrid[X, Y].Density := 100;
        FGrid[X, Y].Flammable := 5;
        FGrid[X, Y].Integrity := 40;
      end;
    mtFire:
      begin
        FGrid[X, Y].Color := $FFFF4000;
        FGrid[X, Y].State := msGas;     // Fire behaves like a gas (rises)
        FGrid[X, Y].Density := 1;
        FGrid[X, Y].Life := 60 + Random(40);
      end;
    mtPowder: // Gunpowder
      begin
        FGrid[X, Y].Color := $FF505050;
        FGrid[X, Y].State := msPowder;
        FGrid[X, Y].Density := 50;
        FGrid[X, Y].Flammable := 10;     // Highly explosive
      end;
    mtNitro: // Nitroglycerin
      begin
        FGrid[X, Y].Color := $FF00FF66; // Cyan-Green
        FGrid[X, Y].State := msLiquid;
        FGrid[X, Y].Density := 35;
        FGrid[X, Y].Flammable := 15;     // Extremely explosive
      end;
    mtOil:
      begin
        FGrid[X, Y].Color := $FF1A1208; // Almost black
        FGrid[X, Y].State := msLiquid;
        FGrid[X, Y].Density := 30;      // Lighter than water (floats)
        FGrid[X, Y].Flammable := 8;
      end;
    mtLava:
      begin
        FGrid[X, Y].Color := $FFFF3300;
        FGrid[X, Y].State := msLiquid;
        FGrid[X, Y].Density := 60;      // Heavy liquid
        FGrid[X, Y].Life := 1000;       // Doesn't cool down naturally easily
      end;
    mtSteam:
      begin
        FGrid[X, Y].Color := $FFD0D0D0; // Light gray smoke
        FGrid[X, Y].State := msGas;
        FGrid[X, Y].Density := 5;
        FGrid[X, Y].Life := 150;        // Dissipates over time
      end;
    mtAcid:
      begin
        FGrid[X, Y].Color := $FFCCFF00; // Toxic yellow-green
        FGrid[X, Y].State := msLiquid;
        FGrid[X, Y].Density := 38;
      end;
    mtSalt:
      begin
        FGrid[X, Y].Color := $FFFFFFFF;
        FGrid[X, Y].State := msPowder;
        FGrid[X, Y].Density := 50;
      end;
    mtPlant:
      begin
        FGrid[X, Y].Color := $FF00AA00;
        FGrid[X, Y].State := msSolid;
        FGrid[X, Y].Density := 100;
        FGrid[X, Y].Flammable := 3;
        FGrid[X, Y].Integrity := 10;
      end;
    mtIce:
      begin
        FGrid[X, Y].Color := $FF99DDFF;
        FGrid[X, Y].State := msSolid;
        FGrid[X, Y].Density := 100;
        FGrid[X, Y].Integrity := 30;
      end;
    mtGlitch:
      begin
        FGrid[X, Y].Color := $FF000000 or TAlphaColor(Random($FFFFFF));
        FGrid[X, Y].State := msSolid;
        FGrid[X, Y].Density := 100;
      end;
    mtTap:
      begin
        FGrid[X, Y].Color := $FFFFFFFF;
        FGrid[X, Y].State := msSolid;
        FGrid[X, Y].Density := 100;
      end;
  end;
end;

function TSkiaPowder.GetCell(X, Y: Integer): TCell;
begin
  if not InBounds(X, Y) then
  begin
    // Return an unbreakable boundary wall for out-of-bounds checks
    Result := Default(TCell);
    Result.MatType := mtWall;
    Result.State := msSolid;
    Result.Density := 1000;
    Result.Integrity := 9999; // Unbreakable borders
    Exit;
  end;
  Result := FGrid[X, Y];
end;

procedure TSkiaPowder.MoveCell(X1, Y1, X2, Y2: Integer);
begin
  FGrid[X2, Y2] := FGrid[X1, Y1];
  FGrid[X1, Y1] := Default(TCell);
  FGrid[X1, Y1].MatType := mtEmpty;
  FGrid[X1, Y1].State := msEmpty;
  FGrid[X2, Y2].Updated := True;
end;

procedure TSkiaPowder.SwapCells(X1, Y1, X2, Y2: Integer);
var
  Temp: TCell;
begin
  Temp := FGrid[X1, Y1];
  FGrid[X1, Y1] := FGrid[X2, Y2];
  FGrid[X2, Y2] := Temp;
  FGrid[X1, Y1].Updated := True;
  FGrid[X2, Y2].Updated := True;
end;

procedure TSkiaPowder.PaintAtMousePos;
var
  P: TPoint;
  dx, dy, DistSq: Integer;
  IsSolidBrush: Boolean;
begin
  P := PointToGrid(FMouseX, FMouseY);
  // Solids should be drawn fully solid. Liquids, Powders, and Gases use a scattered "airbrush" effect.
  IsSolidBrush := (FSelectedMaterial in [mtWall, mtWood, mtPlant, mtIce, mtEraser, mtTap, mtGlitch]);

  for dy := -FBrushRadius to FBrushRadius do
  begin
    for dx := -FBrushRadius to FBrushRadius do
    begin
      DistSq := (dx * dx) + (dy * dy);
      // Only paint inside the circular brush radius
      if (DistSq <= FBrushRadius * FBrushRadius) then
      begin
        // Scatter dynamic materials, but draw solids continuously
        if IsSolidBrush or (Random > 0.5) then
          SetCell(P.X + dx, P.Y + dy, FSelectedMaterial);
      end;
    end;
  end;
end;

{ =============================================================================
  PHYSICS HELPERS & REACTIONS
============================================================================= }

{ Averages two colors. Used for mixing liquids at boundaries to create
  smooth gradients instead of harsh pixel edges. }
function TSkiaPowder.BlendColors(C1, C2: TAlphaColor): TAlphaColor;
var
  R1, G1, B1, R2, G2, B2: Byte;
begin
  R1 := (C1 shr 16) and $FF;
  G1 := (C1 shr 8) and $FF;
  B1 := C1 and $FF;
  R2 := (C2 shr 16) and $FF;
  G2 := (C2 shr 8) and $FF;
  B2 := C2 and $FF;
  Result := $FF000000 or ((R1 + R2) div 2 shl 16) or ((G1 + G2) div 2 shl 8) or ((B1 + B2) div 2);
end;

procedure TSkiaPowder.MixLiquidColors(X, Y: Integer; C: TCell);
var
  Adj: TCell;
begin
  // Only mix different liquids to create smooth gradients at boundaries
  if not (C.MatType in [mtWater, mtOil, mtLava, mtAcid, mtNitro]) then
    Exit;

  if InBounds(X + 1, Y) then
  begin
    Adj := FGrid[X + 1, Y];
    if (Adj.State = msLiquid) and (Adj.MatType <> C.MatType) then
    begin
      FGrid[X, Y].Color := BlendColors(C.Color, Adj.Color);
      FGrid[X + 1, Y].Color := FGrid[X, Y].Color; // Apply same blend to neighbor to avoid flicker
    end;
  end;
end;

{ Ignites a cell if it is flammable. Handles the chain reaction of fire spreading. }
procedure TSkiaPowder.IgniteCell(X, Y: Integer);
var
  Target: TCell;
begin
  if not InBounds(X, Y) then
    Exit;
  Target := FGrid[X, Y];

  if (Target.Flammable > 0) and not Target.Updated and (Target.MatType <> mtFire) then
  begin
    // Explosives detonate instantly!
    if Target.MatType = mtNitro then
    begin
      Explode(X, Y, 5, 15);
      Exit;
    end
    else if Target.MatType = mtPowder then
    begin
      Explode(X, Y, 3, 8);
      Exit;
    end;

    // Normal flammable materials catch fire
    FGrid[X, Y].MatType := mtFire;
    FGrid[X, Y].State := msGas;
    FGrid[X, Y].Density := 1;
    FGrid[X, Y].Color := $FFFF4000;
    FGrid[X, Y].Life := 40 + Random(Target.Flammable * 5);
    FGrid[X, Y].Updated := True;
  end
  else if (Target.MatType = mtWater) then
  begin
    // Fire turns water into steam
    SetCell(X, Y, mtSteam);
  end;
end;

{ Applies blast pressure to a cell. Solids take damage to their Integrity (HP).
  Liquids/Powders get Velocity added to make them fly away. }
procedure TSkiaPowder.ApplyPressure(X, Y, Force: Integer);
var
  Target: TCell;
begin
  if not InBounds(X, Y) then
    Exit;
  Target := FGrid[X, Y];

  // Walls and Solids have Integrity (HP). If Pressure > HP, they break.
  if Target.State = msSolid then
  begin
    if Target.Integrity > 0 then
    begin
      FGrid[X, Y].Integrity := FGrid[X, Y].Integrity - Force;
      if FGrid[X, Y].Integrity <= 0 then
        SetCell(X, Y, mtEmpty); // Wall bursts into dust
      Exit; // Solid block fully absorbs the blast
    end;
  end;

  // Liquids and Powders get pushed away by the shockwave
  if Target.State in [msLiquid, msPowder, msGas] then
  begin
    FGrid[X, Y].Velocity := Max(FGrid[X, Y].Velocity, Force);
  end;
end;

{ Creates an explosion with a shockwave. Damages solids and knocks back fluids. }
procedure TSkiaPowder.Explode(X, Y, Radius, Force: Integer);
var
  dx, dy, Dist, Power: Integer;
begin
  SetCell(X, Y, mtFire);

  // Create a circular shockwave
  for dy := -Radius to Radius do
  begin
    for dx := -Radius to Radius do
    begin
      Dist := Round(Sqrt(dx * dx + dy * dy));
      if Dist <= Radius then
      begin
        if (dx = 0) and (dy = 0) then
          Continue;

        // Calculate power based on distance from the center
        Power := Force - (Dist * (Force div (Radius + 1)));
        if Power <= 0 then
          Continue;

        // Apply pressure to the surrounding cells
        ApplyPressure(X + dx, Y + dy, Power);

        // Ignite flammables caught in the blast
        IgniteCell(X + dx, Y + dy);
      end;
    end;
  end;
end;

{ Movement logic for Powders (Sand, Salt, Gunpowder).
  1. If blasted by an explosion, fly upwards/sideways.
  2. Fall straight down if empty.
  3. Sink in liquids/gases if powder is denser.
  4. Slide diagonally to simulate piles. }
procedure TSkiaPowder.MovePowder(X, Y: Integer; const C: TCell);
var
  Below, BelowL, BelowR: TCell;
  Dir: Integer;
begin
  // If material has Velocity (from an explosion), make it fly!
  if C.Velocity > 0 then
  begin
    Dir := IfThen(Random > 0.5, 1, -1);
    // IMPORTANT: Decay velocity BEFORE moving, otherwise we update an empty cell!
    FGrid[X, Y].Velocity := C.Velocity - 1;

    // Try to move sideways/diagonally upwards
    if GetCell(X + Dir, Y - 1).State = msEmpty then
      MoveCell(X, Y, X + Dir, Y - 1)
    else if GetCell(X + Dir, Y).State = msEmpty then
      MoveCell(X, Y, X + Dir, Y)
    else if GetCell(X, Y - 1).State = msEmpty then
      MoveCell(X, Y, X, Y - 1);

    Exit;
  end;

  // Standard gravity sinking
  Below := GetCell(X, Y + 1);
  if (Below.State = msEmpty) then
    MoveCell(X, Y, X, Y + 1)
  else if (Below.State in [msLiquid, msGas]) and (Below.Density < C.Density) then
    SwapCells(X, Y, X, Y + 1) // Powders sink in liquids
  else
  begin
    // Try diagonal sliding to create natural looking piles
    Dir := IfThen(Random > 0.5, 1, -1);
    BelowR := GetCell(X + Dir, Y + 1);
    BelowL := GetCell(X - Dir, Y + 1);
    if (BelowR.State = msEmpty) then
      MoveCell(X, Y, X + Dir, Y + 1)
    else if (BelowR.State in [msLiquid, msGas]) and (BelowR.Density < C.Density) then
      SwapCells(X, Y, X + Dir, Y + 1)
    else if (BelowL.State = msEmpty) then
      MoveCell(X, Y, X - Dir, Y + 1)
    else if (BelowL.State in [msLiquid, msGas]) and (BelowL.Density < C.Density) then
      SwapCells(X, Y, X - Dir, Y + 1);
  end;
end;

{ Movement logic for Liquids (Water, Oil, Acid, Lava).
  1. If blasted, fly.
  2. Fall down / sink if denser.
  3. Flow horizontally to create puddles.
  4. Diagonal flow if horizontal is blocked. }
procedure TSkiaPowder.MoveLiquid(X, Y, Dir: Integer; const C: TCell);
var
  Below, BelowL, BelowR, SideL, SideR: TCell;
begin
  // Liquids can also be blasted by explosions
  if C.Velocity > 0 then
  begin
    Dir := IfThen(Random > 0.5, 1, -1);
    FGrid[X, Y].Velocity := C.Velocity - 1; // Decay velocity first

    if GetCell(X + Dir, Y - 1).State = msEmpty then
      MoveCell(X, Y, X + Dir, Y - 1)
    else if GetCell(X + Dir, Y).State = msEmpty then
      MoveCell(X, Y, X + Dir, Y)
    else if GetCell(X, Y - 1).State = msEmpty then
      MoveCell(X, Y, X, Y - 1);
    Exit;
  end;

  Below := GetCell(X, Y + 1);
  // 1. Try straight down
  if (Below.State = msEmpty) then
  begin
    MoveCell(X, Y, X, Y + 1);
    Exit;
  end;
  if (Below.State in [msLiquid, msGas]) and (Below.Density < C.Density) then
  begin
    SwapCells(X, Y, X, Y + 1);
    Exit;
  end;

  // 2. Try horizontal flow FIRST (This creates flat puddles!)
  SideR := GetCell(X + Dir, Y);
  if (SideR.State = msEmpty) then
  begin
    MoveCell(X, Y, X + Dir, Y);
    Exit;
  end;
  if (SideR.State in [msLiquid, msGas]) and (SideR.Density < C.Density) then
  begin
    SwapCells(X, Y, X + Dir, Y);
    Exit;
  end;

  SideL := GetCell(X - Dir, Y);
  if (SideL.State = msEmpty) then
  begin
    MoveCell(X, Y, X - Dir, Y);
    Exit;
  end;
  if (SideL.State in [msLiquid, msGas]) and (SideL.Density < C.Density) then
  begin
    SwapCells(X, Y, X - Dir, Y);
    Exit;
  end;

  // 3. Try diagonal down LAST (Only if horizontal is completely blocked)
  BelowR := GetCell(X + Dir, Y + 1);
  if (BelowR.State = msEmpty) then
  begin
    MoveCell(X, Y, X + Dir, Y + 1);
    Exit;
  end;
  if (BelowR.State in [msLiquid, msGas]) and (BelowR.Density < C.Density) then
  begin
    SwapCells(X, Y, X + Dir, Y + 1);
    Exit;
  end;

  BelowL := GetCell(X - Dir, Y + 1);
  if (BelowL.State = msEmpty) then
  begin
    MoveCell(X, Y, X - Dir, Y + 1);
    Exit;
  end;
  if (BelowL.State in [msLiquid, msGas]) and (BelowL.Density < C.Density) then
  begin
    SwapCells(X, Y, X - Dir, Y + 1);
    Exit;
  end;
end;

{ Movement logic for Gases (Fire, Steam).
  Includes entropy so gases spread out and dissipate naturally rather than
  stacking up in straight vertical lines. }
procedure TSkiaPowder.MoveGas(X, Y, Dir: Integer; const C: TCell);
var
  Above, SideR, SideL, DiagR, DiagL: TCell;
begin
  // Entropy: Gases randomly drift sideways to look like real smoke/vapor
  if Random > 0.8 then
  begin
    Dir := IfThen(Random > 0.5, 1, -1);
    SideR := GetCell(X + Dir, Y);
    if (SideR.State = msEmpty) then
    begin
      MoveCell(X, Y, X + Dir, Y);
      Exit;
    end;
  end;

  Above := GetCell(X, Y - 1);
  // 1. Try straight up
  if (Above.State = msEmpty) then
  begin
    MoveCell(X, Y, X, Y - 1);
    Exit;
  end;
  if (Above.State in [msLiquid, msGas]) and (Above.Density > C.Density) then
  begin
    SwapCells(X, Y, X, Y - 1);
    Exit;
  end;

  // 2. Try horizontal scatter (helps gases spread out)
  SideR := GetCell(X + Dir, Y);
  if (SideR.State = msEmpty) then
  begin
    MoveCell(X, Y, X + Dir, Y);
    Exit;
  end;
  SideL := GetCell(X - Dir, Y);
  if (SideL.State = msEmpty) then
  begin
    MoveCell(X, Y, X - Dir, Y);
    Exit;
  end;

  // 3. Try diagonal up
  DiagR := GetCell(X + Dir, Y - 1);
  if (DiagR.State = msEmpty) then
  begin
    MoveCell(X, Y, X + Dir, Y - 1);
    Exit;
  end;
  DiagL := GetCell(X - Dir, Y - 1);
  if (DiagL.State = msEmpty) then
  begin
    MoveCell(X, Y, X - Dir, Y - 1);
    Exit;
  end;
end;

{ The Cellular Automata Brain. Handles all chemical and physical reactions
  between adjacent cells (e.g., Lava+Water=Stone, Acid eating matter, etc.) }
procedure TSkiaPowder.ProcessReactions(X, Y: Integer; var C: TCell);
var
  dx: Integer;
  Adj: TCell;
  HasOxygen, IsHotNearby, HasWater, HasSand, HasAcid, HasIceAside, HasSalt: Boolean;
begin
  if C.MatType = mtFire then
  begin
    FGrid[X, Y].Life := FGrid[X, Y].Life - 1;

    // Fire needs oxygen (empty space) to keep burning intensely
    HasOxygen := (GetCell(X + 1, Y).State = msEmpty) or (GetCell(X - 1, Y).State = msEmpty) or (GetCell(X, Y + 1).State = msEmpty) or (GetCell(X, Y - 1).State = msEmpty);
    if not HasOxygen then
      FGrid[X, Y].Life := FGrid[X, Y].Life - 2; // Suffocate faster

    // Visual color shift based on remaining life
    if FGrid[X, Y].Life > 30 then
      FGrid[X, Y].Color := $FFFFFF00 // Yellow hot
    else
      FGrid[X, Y].Color := $FFFF4000; // Orange dying

    if FGrid[X, Y].Life <= 0 then
    begin
      SetCell(X, Y, mtEmpty);
      Exit;
    end;

    // Spread fire to neighboring flammables
    IgniteCell(X + 1, Y);
    IgniteCell(X - 1, Y);
    IgniteCell(X, Y + 1);
    IgniteCell(X, Y - 1);
  end
  else if C.MatType = mtLava then
  begin
    // Scan adjacent cells for potential reactions
    HasWater := (GetCell(X + 1, Y).MatType = mtWater) or (GetCell(X - 1, Y).MatType = mtWater) or (GetCell(X, Y + 1).MatType = mtWater) or (GetCell(X, Y - 1).MatType = mtWater);
    HasSand := (GetCell(X + 1, Y).MatType = mtSand) or (GetCell(X - 1, Y).MatType = mtSand) or (GetCell(X, Y + 1).MatType = mtSand) or (GetCell(X, Y - 1).MatType = mtSand);
    HasAcid := (GetCell(X + 1, Y).MatType = mtAcid) or (GetCell(X - 1, Y).MatType = mtAcid) or (GetCell(X, Y + 1).MatType = mtAcid) or (GetCell(X, Y - 1).MatType = mtAcid);
    HasIceAside := (GetCell(X + 1, Y).MatType = mtIce) or (GetCell(X - 1, Y).MatType = mtIce) or (GetCell(X, Y - 1).MatType = mtIce);
    HasSalt := (GetCell(X + 1, Y).MatType = mtSalt) or (GetCell(X - 1, Y).MatType = mtSalt) or (GetCell(X, Y + 1).MatType = mtSalt) or (GetCell(X, Y - 1).MatType = mtSalt);

    // Reaction 1: Lava + Water = Stone + Steam
    if HasWater then
    begin
      if Random > 0.4 then
      begin
        SetCell(X, Y, mtWall); // Lava cools to Stone
        if GetCell(X + 1, Y).MatType = mtWater then
          SetCell(X + 1, Y, mtSteam)
        else if GetCell(X - 1, Y).MatType = mtWater then
          SetCell(X - 1, Y, mtSteam)
        else if GetCell(X, Y + 1).MatType = mtWater then
          SetCell(X, Y + 1, mtSteam)
        else if GetCell(X, Y - 1).MatType = mtWater then
          SetCell(X, Y - 1, mtSteam);
        Exit;
      end;
    end;

    // Reaction 2: Lava melts Ice horizontally
    if HasIceAside then
    begin
      if Random > 0.5 then
      begin
        if GetCell(X + 1, Y).MatType = mtIce then
          SetCell(X + 1, Y, mtWater)
        else if GetCell(X - 1, Y).MatType = mtIce then
          SetCell(X - 1, Y, mtWater)
        else if GetCell(X, Y - 1).MatType = mtIce then
          SetCell(X, Y - 1, mtWater);
        Exit;
      end;
    end;
    // Lava melts Ice below it instantly to steam and moves down
    if GetCell(X, Y + 1).MatType = mtIce then
    begin
      SetCell(X, Y + 1, mtSteam);
      MoveCell(X, Y, X, Y + 1);
      Exit;
    end;

    // Reaction 3: Lava boils Acid away
    if HasAcid then
    begin
      if Random > 0.5 then
      begin
        if GetCell(X + 1, Y).MatType = mtAcid then
          SetCell(X + 1, Y, mtSteam)
        else if GetCell(X - 1, Y).MatType = mtAcid then
          SetCell(X - 1, Y, mtSteam)
        else if GetCell(X, Y + 1).MatType = mtAcid then
          SetCell(X, Y + 1, mtSteam)
        else if GetCell(X, Y - 1).MatType = mtAcid then
          SetCell(X, Y - 1, mtSteam);
        Exit;
      end;
    end;

    // Reaction 4: Lava slowly melts Sand into Lava (expands the lava puddle)
    if HasSand then
    begin
      if Random > 0.75 then
      begin
        if GetCell(X + 1, Y).MatType = mtSand then
          SetCell(X + 1, Y, mtLava)
        else if GetCell(X - 1, Y).MatType = mtSand then
          SetCell(X - 1, Y, mtLava)
        else if GetCell(X, Y + 1).MatType = mtSand then
          SetCell(X, Y + 1, mtLava)
        else if GetCell(X, Y - 1).MatType = mtSand then
          SetCell(X, Y - 1, mtLava);
        Exit;
      end;
    end;

    // Reaction 5: Lava melts Salt into Lava
    if HasSalt then
    begin
      if Random > 0.7 then
      begin
        if GetCell(X + 1, Y).MatType = mtSalt then
          SetCell(X + 1, Y, mtLava)
        else if GetCell(X - 1, Y).MatType = mtSalt then
          SetCell(X - 1, Y, mtLava)
        else if GetCell(X, Y + 1).MatType = mtSalt then
          SetCell(X, Y + 1, mtLava)
        else if GetCell(X, Y - 1).MatType = mtSalt then
          SetCell(X, Y - 1, mtLava);
        Exit;
      end;
    end;

    // Reaction 6: Ignite flammables (Wood, Plant, Oil, Nitro, Powder) - slower to prevent instant map nukes
    if Random > 0.75 then
    begin
      IgniteCell(X + 1, Y);
      IgniteCell(X - 1, Y);
      IgniteCell(X, Y + 1);
      IgniteCell(X, Y - 1);
    end;

    // Volcano Eruption: Lava builds pressure and erupts upwards if blocked
    if (GetCell(X, Y - 1).State = msSolid) and (Random > 0.98) then
      Explode(X, Y, 2, 6);
  end
  else if C.MatType = mtAcid then
  begin
    // Acid aggressively eats the cell below it first (since gravity pulls it onto things)
    if InBounds(X, Y + 1) and (FGrid[X, Y + 1].MatType in [mtSand, mtWood, mtWall, mtPlant, mtIce, mtSalt, mtPowder, mtNitro]) then
    begin
      SetCell(X, Y + 1, mtEmpty);
      if Random > 0.6 then
        SetCell(X, Y, mtEmpty); // Acid consumes itself
      Exit;
    end;

    // Then check sides randomly
    if Random > 0.5 then
    begin
      dx := IfThen(Random > 0.5, 1, -1);
      if InBounds(X + dx, Y) and (FGrid[X + dx, Y].MatType in [mtSand, mtWood, mtWall, mtPlant, mtIce, mtSalt, mtPowder, mtNitro]) then
      begin
        SetCell(X + dx, Y, mtEmpty);
        if Random > 0.8 then
          SetCell(X, Y, mtEmpty);
        Exit;
      end;
    end;

    // Acid gets neutralized by water
    if (GetCell(X + 1, Y).MatType = mtWater) or (GetCell(X - 1, Y).MatType = mtWater) or (GetCell(X, Y + 1).MatType = mtWater) or (GetCell(X, Y - 1).MatType = mtWater) then
    begin
      if Random > 0.8 then
        SetCell(X, Y, mtEmpty);
    end;
  end
  else if C.MatType = mtSteam then
  begin
    FGrid[X, Y].Life := FGrid[X, Y].Life - 1;
    if FGrid[X, Y].Life <= 0 then
      SetCell(X, Y, mtEmpty); // Evaporates completely
  end
  else if C.MatType = mtSalt then
  begin
    // Salt dissolves in water
    if (GetCell(X + 1, Y).MatType = mtWater) or (GetCell(X - 1, Y).MatType = mtWater) or (GetCell(X, Y + 1).MatType = mtWater) or (GetCell(X, Y - 1).MatType = mtWater) then
      SetCell(X, Y, mtEmpty);
  end
  else if C.MatType = mtIce then
  begin
    IsHotNearby := (GetCell(X + 1, Y).MatType = mtFire) or (GetCell(X + 1, Y).MatType = mtLava) or (GetCell(X - 1, Y).MatType = mtFire) or (GetCell(X - 1, Y).MatType = mtLava) or (GetCell(X, Y + 1).MatType = mtFire) or (GetCell(X, Y + 1).MatType = mtLava) or (GetCell(X, Y - 1).MatType = mtFire) or (GetCell(X, Y - 1).MatType = mtLava);

    if IsHotNearby then
    begin
      SetCell(X, Y, mtWater);
      Exit;
    end
    else if (GetCell(X, Y + 1).MatType = mtWater) or (GetCell(X + 1, Y).MatType = mtWater) or (GetCell(X - 1, Y).MatType = mtWater) then
    begin
      // Melts slowly in contact with water
      if Random > 0.99 then
        SetCell(X, Y, mtWater);
    end;
  end
  else if C.MatType = mtPlant then
  begin
    // Plants grow towards water or upwards
    if Random > 0.8 then
    begin
      if GetCell(X, Y - 1).State = msEmpty then
        SetCell(X, Y - 1, mtPlant)
      else if GetCell(X + 1, Y).MatType = mtWater then
        SetCell(X + 1, Y, mtPlant)
      else if GetCell(X - 1, Y).MatType = mtWater then
        SetCell(X - 1, Y, mtPlant)
      else if GetCell(X, Y + 1).MatType = mtWater then
        SetCell(X, Y + 1, mtPlant);
    end;
  end
  else if C.MatType = mtGlitch then
  begin
    FGrid[X, Y].Color := $FF000000 or TAlphaColor(Random($FFFFFF));
    // Spread glitch synchronously to avoid heap corruption
    if Random > 0.8 then
    begin
      case Random(4) of
        0:
          if GetCell(X + 1, Y).State = msEmpty then
            SetCell(X + 1, Y, mtGlitch);
        1:
          if GetCell(X - 1, Y).State = msEmpty then
            SetCell(X - 1, Y, mtGlitch);
        2:
          if GetCell(X, Y + 1).State = msEmpty then
            SetCell(X, Y + 1, mtGlitch);
        3:
          if GetCell(X, Y - 1).State = msEmpty then
            SetCell(X, Y - 1, mtGlitch);
      end;
    end;
  end
  else if C.MatType = mtTap then
  begin
    // Tap scans neighbors to find out what to clone
    if FGrid[X, Y].SpawnType = mtTap then
    begin
      // Don't learn from empty air
      if (GetCell(X + 1, Y).MatType <> mtTap) and (GetCell(X + 1, Y).MatType <> mtEmpty) then
        FGrid[X, Y].SpawnType := GetCell(X + 1, Y).MatType
      else if (GetCell(X - 1, Y).MatType <> mtTap) and (GetCell(X - 1, Y).MatType <> mtEmpty) then
        FGrid[X, Y].SpawnType := GetCell(X - 1, Y).MatType
      else if (GetCell(X, Y + 1).MatType <> mtTap) and (GetCell(X, Y + 1).MatType <> mtEmpty) then
        FGrid[X, Y].SpawnType := GetCell(X, Y + 1).MatType
      else if (GetCell(X, Y - 1).MatType <> mtTap) and (GetCell(X, Y - 1).MatType <> mtEmpty) then
        FGrid[X, Y].SpawnType := GetCell(X, Y - 1).MatType;
    end
    else if FGrid[X, Y].SpawnType <> mtEmpty then
    begin
      // Spawn the cloned material randomly
      if Random > 0.5 then
      begin
        case Random(4) of
          0:
            if GetCell(X + 1, Y).State = msEmpty then
              SetCell(X + 1, Y, FGrid[X, Y].SpawnType);
          1:
            if GetCell(X - 1, Y).State = msEmpty then
              SetCell(X - 1, Y, FGrid[X, Y].SpawnType);
          2:
            if GetCell(X, Y + 1).State = msEmpty then
              SetCell(X, Y + 1, FGrid[X, Y].SpawnType);
          3:
            if GetCell(X, Y - 1).State = msEmpty then
              SetCell(X, Y - 1, FGrid[X, Y].SpawnType);
        end;
      end;
    end;
  end;

  // Mix colors at the end if it's a liquid
  if C.State = msLiquid then
    MixLiquidColors(X, Y, C);
end;

{ =============================================================================
  PHYSICS UPDATE LOOP
  The heart of the simulation.
  We split this into two passes to fix the "mirror mountain" gas stacking bug.
  Pass 1 goes Bottom-to-Top for Gravity (Solids, Powders, Liquids).
  Pass 2 goes Top-to-Bottom for Buoyancy (Gases, Fire, Steam).
============================================================================= }
procedure TSkiaPowder.DoPhysicsUpdate(DeltaSec: Double);
var
  X, Y, GridX, Dir: Integer;
  C: TCell;
begin
  if not FActive then
    Exit;
  FLock.Acquire;
  try
    // Reset Updated flags for this frame
    for Y := 0 to FGridH - 1 do
      for X := 0 to FGridW - 1 do
        FGrid[X, Y].Updated := False;

    // PASS 1: Bottom to Top. Process Solids, Powders, and Liquids.
    for Y := FGridH - 1 downto 0 do
    begin
      // Randomize horizontal iteration direction to prevent asymmetric flow
      Dir := IfThen(Random > 0.5, 1, -1);
      for X := 0 to FGridW - 1 do
      begin
        GridX := IfThen(Dir = 1, X, FGridW - 1 - X);
        C := FGrid[GridX, Y];

        if (C.MatType = mtEmpty) or (C.State = msGas) then
          Continue; // Skip gases

        // 1. Process specific reactions (Fire, Acid, Ice melting, etc.) ALWAYS!
        ProcessReactions(GridX, Y, C);

        // Re-fetch cell as it might have changed (e.g., Ice -> Water)
        C := FGrid[GridX, Y];
        if (C.MatType = mtEmpty) or (C.State = msGas) or C.Updated then
          Continue;

        // 2. Process movement based on state
        case C.State of
          msPowder:
            MovePowder(GridX, Y, C);
          msLiquid:
            MoveLiquid(GridX, Y, Dir, C);
        end;
      end;
    end;

    // PASS 2: Top to Bottom. Process Gases.
    // This prevents the "mirror mountain" stacking bug where gases can't rise.
    for Y := 0 to FGridH - 1 do
    begin
      Dir := IfThen(Random > 0.5, 1, -1);
      for X := 0 to FGridW - 1 do
      begin
        GridX := IfThen(Dir = 1, X, FGridW - 1 - X);
        C := FGrid[GridX, Y];

        if (C.MatType = mtEmpty) or (C.State <> msGas) then
          Continue;

        ProcessReactions(GridX, Y, C);

        C := FGrid[GridX, Y];
        if (C.MatType = mtEmpty) or (C.State <> msGas) or C.Updated then
          Continue;

        MoveGas(GridX, Y, Dir, C);
      end;
    end;

  finally
    FLock.Release;
  end;
end;

{ =============================================================================
  THREADING & RENDERING
  Physics run in a background thread. Redraw is safely queued back to the
  main UI thread to prevent tearing and heap corruption.
============================================================================= }
procedure TSkiaPowder.SafeInvalidate;
begin
  if csDestroying in ComponentState then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      if not (csDestroying in ComponentState) and Assigned(Self) then
      begin
        Redraw;
        Repaint;
      end;
    end);
end;

procedure TSkiaPowder.StartThread;
begin
  if Assigned(FThread) then
    Exit;
  // Run physics loop in anonymous thread to keep UI responsive
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      LastTime, NowTime, DeltaMS: Cardinal;
    begin
      LastTime := TThread.GetTickCount;
      while not TThread.CheckTerminated do
      begin
        NowTime := TThread.GetTickCount;
        DeltaMS := NowTime - LastTime;
        if DeltaMS = 0 then
          DeltaMS := 1;
        LastTime := NowTime;

        if FActive then
        begin
          DoPhysicsUpdate(DeltaMS / 1000);
          SafeInvalidate;
        end;
        Sleep(16); // Cap at roughly 60 FPS
      end;
    end);
  FThread.FreeOnTerminate := True;
  FThread.Start;
end;

procedure TSkiaPowder.StopThread;
begin
  FActive := False;
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    Sleep(50);
  end;
end;

procedure TSkiaPowder.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  FIsMouseDown := True;
  FMouseX := X;
  FMouseY := Y;
  inherited;
end;

procedure TSkiaPowder.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  FMouseX := X;
  FMouseY := Y;
  inherited;
end;

procedure TSkiaPowder.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  FIsMouseDown := False;
  inherited;
end;

function TSkiaPowder.GetCellWidth: Single;
begin
  if FGridW = 0 then
    Exit(1);
  Result := Self.Width / FGridW;
end;

function TSkiaPowder.GetCellHeight: Single;
begin
  if FGridH = 0 then
    Exit(1);
  Result := Self.Height / FGridH;
end;

function TSkiaPowder.PointToGrid(X, Y: Single): TPoint;
begin
  Result.X := Trunc(X / GetCellWidth);
  Result.Y := Trunc(Y / GetCellHeight);
end;

function TSkiaPowder.GetMaterialName(MatType: TMaterialType): string;
begin
  case MatType of
    mtSand:
      Result := 'Sand';
    mtWater:
      Result := 'Water';
    mtWall:
      Result := 'Wall';
    mtWood:
      Result := 'Wood';
    mtFire:
      Result := 'Fire';
    mtPowder:
      Result := 'Powder';
    mtNitro:
      Result := 'Nitro';
    mtGlitch:
      Result := 'Glitch';
    mtTap:
      Result := 'Tap';
    mtEraser:
      Result := 'Eraser';
    mtOil:
      Result := 'Oil';
    mtLava:
      Result := 'Lava';
    mtSteam:
      Result := 'Steam';
    mtAcid:
      Result := 'Acid';
    mtSalt:
      Result := 'Salt';
    mtPlant:
      Result := 'Plant';
    mtIce:
      Result := 'Ice';
  else
    Result := 'Unknown';
  end;
end;

{ Renders the grid to the GPU canvas. Iterates through all cells and draws
  colored rectangles. Also draws a custom brush cursor. }
procedure TSkiaPowder.DrawGrid(const ACanvas: ISkCanvas);
var
  X, Y: Integer;
  Cell: TCell;
  Paint: ISkPaint;
  CellW, CellH: Single;
  BrushP: TPoint;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := False; // Crisp pixel-art look

  // Draw dark background
  Paint.Color := $FF050508;
  ACanvas.DrawPaint(Paint);

  CellW := GetCellWidth;
  CellH := GetCellHeight;

  FLock.Acquire;
  try
    // Render active cells
    for Y := 0 to FGridH - 1 do
    begin
      for X := 0 to FGridW - 1 do
      begin
        Cell := FGrid[X, Y];
        if Cell.MatType <> mtEmpty then
        begin
          Paint.Color := Cell.Color;
          ACanvas.DrawRect(TRectF.Create(X * CellW, Y * CellH, (X + 1) * CellW, (Y + 1) * CellH), Paint);
        end;
      end;
    end;

    // Render the brush cursor outline
    if FIsMouseDown then
    begin
      BrushP := PointToGrid(FMouseX, FMouseY);
      Paint.Color := TAlphaColors.White;
      Paint.Alpha := 100;
      Paint.Style := TSkPaintStyle.Stroke;
      Paint.StrokeWidth := 2;
      Paint.AntiAlias := True;
      // Draw circle to indicate the brush radius
      ACanvas.DrawCircle(PointF(BrushP.X * CellW + (CellW / 2), BrushP.Y * CellH + (CellH / 2)), FBrushRadius * CellW, Paint);
    end;
  finally
    FLock.Release;
  end;
end;

procedure TSkiaPowder.Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single);
begin
  DrawGrid(ACanvas);

  // Paint directly into the grid if the mouse is held down
  if FIsMouseDown then
  begin
    FLock.Acquire;
    try
      PaintAtMousePos;
    finally
      FLock.Release;
    end;
  end;
end;

end.

