unit Unit2;

interface
uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Skia,
  FMX.StdCtrls, FMX.Layouts, uSkiaPowder;
type
  TForm2 = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    FToolBar: TLayout;
    FPowderGame: TSkiaPowder;
    procedure CreateToolbar;
    procedure ToolButtonClick(Sender: TObject);
  public
    { Public-Deklarationen }
  end;
var
  Form2: TForm2;
implementation
{$R *.fmx}

procedure TForm2.FormCreate(Sender: TObject);
begin
  // Create the SkiaPowder Game Control first (Client fills the rest of the screen)
  FPowderGame := TSkiaPowder.Create(Self);
  FPowderGame.Parent := Self;
  FPowderGame.Align := TAlignLayout.Client;
  FPowderGame.HitTest := True;
  // Create a simple Layout as a Toolbar on the Left
  FToolBar := TLayout.Create(Self);
  FToolBar.Parent := Self;
  FToolBar.Align := TAlignLayout.Left;
  FToolBar.Width := 110;
  FToolBar.Padding.Rect := TRectF.Create(5, 5, 5, 5);
  // Generate UI Buttons for all available materials
  CreateToolbar;
end;
procedure TForm2.CreateToolbar;
var
  MatType: TMaterialType;
  Btn: TButton;
  YPos: Single;
begin
  YPos := 5;
  for MatType := Low(TMaterialType) to High(TMaterialType) do
  begin
    if MatType = mtEmpty then Continue; // Skip mtEmpty state
    Btn := TButton.Create(Self);
    Btn.Parent := FToolBar;
    Btn.Position.X := 5;
    Btn.Position.Y := YPos;
    Btn.Width := 95;
    Btn.Height := 32;
    Btn.Text := FPowderGame.GetMaterialName(MatType);
    Btn.Tag := Ord(MatType);
    Btn.OnClick := ToolButtonClick;
    // Styling
    Btn.StyledSettings := Btn.StyledSettings - [TStyledSetting.Size, TStyledSetting.Style];
    Btn.TextSettings.Font.Size := 11;
    Btn.TextSettings.Font.Style := Btn.TextSettings.Font.Style + [TFontStyle.fsBold];
    // Calculate next Y position (Height + 8px margin)
    YPos := YPos + 40;
  end;
end;
procedure TForm2.ToolButtonClick(Sender: TObject);
begin
  if Sender is TButton then
  begin
    // Set the selected material in the Powder Game
    FPowderGame.SelectedMaterial := TMaterialType(TButton(Sender).Tag);
  end;
end;
end.
