{
  Copyright (C) 2009 Robbert Latumahina

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License as published by
  the Free Software Foundation; either version 2.1 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

  midipatterngui.pas
}

unit midipatterngui;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, midi, midigui, graphics,
  track, LCLType, globalconst, global_command, global, pattern, ComCtrls,
  imglist, LCLintf, Menus, patterngui;

type

  { TMidiPatternGUI }

  TMidiPatternGUI = class(TPatternGUI)
  private
    FModel: TMidiPattern;

    bmp: TBitmap;
    FCursorPosition: Integer;
    FOldCursorPosition: Integer;
    FCacheIsDirty: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update(Subject: THybridPersistentModel); reintroduce; override;
    procedure UpdateGUI;
    procedure RecalculateSynchronize;
    procedure ChangeZoomX(Sender: TObject);
    procedure Connect; override;
    procedure Disconnect; override;
    procedure Invalidate; override;
    procedure EraseBackground(DC: HDC); override;
    procedure Paint; override;
    procedure DragDrop(Source: TObject; X, Y: Integer); override;

    function GetModel: THybridPersistentModel; override;
    procedure SetModel(AModel: THybridPersistentModel); override;

    property CursorPosition: Integer read FCursorPosition write FCursorPosition;
    property CacheIsDirty: Boolean read FCacheIsDirty write FCacheIsDirty;
    property Model: THybridPersistentModel read GetModel write SetModel;
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y:Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y:Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure DragOver(Source: TObject; X, Y: Integer; State: TDragState;
                    var Accept: Boolean); override;
    procedure MyEndDrag(Sender, Target: TObject; X, Y: Integer);
    function GetDragImages: TDragImageList; override;
  end;


implementation

uses
  utils, trackcommand;

{ TMidiPatternGUI }

constructor TMidiPatternGUI.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  bmp := TBitmap.Create;
  FCacheIsDirty := True;

  FCursorPosition := 0;
  Height := 15;
  RecalculateSynchronize;

  OnEndDrag := @MyEndDrag;

  {ChangeControlStyle(Self, [csDisplayDragImage], [], True);}
end;

destructor TMidiPatternGUI.Destroy;
begin
  bmp.Free;

  inherited;
end;

procedure TMidiPatternGUI.UpdateGUI;
begin
  Invalidate;
end;

procedure TMidiPatternGUI.RecalculateSynchronize;
begin
  //FPatternLength := Round(WaveForm.SampleRate * (60 / FRealBPM)) * 4; // TODO choose next multiple of 4
end;

procedure TMidiPatternGUI.ChangeZoomX(Sender: TObject);
begin
  // Zooming is GUI stuff and only needs to update itself
end;

procedure TMidiPatternGUI.EraseBackground(DC: HDC);
begin
  inherited EraseBackground(DC);
end;

procedure TMidiPatternGUI.Paint;
var
  lCursorPos: Integer;
begin
  //if FCacheIsDirty then
  begin
    bmp.Canvas.Clear;

    Top := Position;
    Width := Parent.Width;
    bmp.Height := Height;
    bmp.Width := Width;

    bmp.Canvas.Brush.Color := clLtGray;
    bmp.Canvas.Rectangle(0, 0, 15, Height);

    bmp.Canvas.Pen.Color := clGray;
    bmp.Canvas.Brush.Color := clGray;

    if FModel.Playing then
    begin
      bmp.Canvas.Rectangle(3, 3, 12, Height - 3);
    end
    else
    begin
      bmp.Canvas.Polygon([Point(3, 2), Point(12, Height div 2), Point(3, Height - 3)]);
    end;

    bmp.Canvas.Brush.Color := clLtGray;
    bmp.Canvas.Clipping := False;
    bmp.Canvas.Rectangle(15, 0, Width, Height);

    bmp.Canvas.TextOut(17, 2, Text);
    FCacheIsDirty := False;
  end;

  Canvas.Draw(0, 0, bmp);

  // Draw live pattern cursor
  lCursorPos := Round(Width * (FCursorPosition / PatternLength));
  if FOldCursorPosition <> lCursorPos then
  begin
    Canvas.Pen.Color := clRed;
    Canvas.Line(lCursorPos, 0, lCursorPos, Height);
    Canvas.Pen.Color := clLtGray;

    FOldCursorPosition := lCursorPos;
  end;

  inherited Paint;
end;

procedure TMidiPatternGUI.MouseDown(Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
var
  lSchedulePattern: TSchedulePatternCommand;
begin
  if Button = mbLeft then
  begin
    Self.BeginDrag(False, 5);

    // TODO Playing pattern should be scheduler
    if (X - Self.Left) < 15 then
    begin
      Scheduled := True;

      lSchedulePattern := TSchedulePatternCommand.Create(ObjectID);
      try
        lSchedulePattern.ObjectIdList.Add(Self.ObjectID);
        lSchedulePattern.TrackID := Self.ObjectOwnerID;
        lSchedulePattern.Persist := False;
        GCommandQueue.PushCommand(lSchedulePattern);
      except
        on e:exception do
        begin
          DBLog('Internal error: ' + e.message);
          lSchedulePattern.Free;
        end;
      end;
    end
    else
    begin
      Selected := True;
    end;

    GSettings.SelectedObject := Self;

    FCacheIsDirty := True;

    //DoPatternRefreshGUI;
  end
  else if Button = mbRight then
  begin
    //
  end;


  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TMidiPatternGUI.MouseUp(Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  FCacheIsDirty := True;

  inherited MouseUp(Button, Shift, X, Y);

  //DoPatternRefreshGUI;

end;

procedure TMidiPatternGUI.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
end;

procedure TMidiPatternGUI.DragDrop(Source: TObject; X, Y: Integer);
{var
  lTreeView: TTreeView;}
begin
  inherited DragDrop(Source, X, Y);
end;

function TMidiPatternGUI.GetModel: THybridPersistentModel;
begin
  Result := THybridPersistentModel(FModel);
end;

procedure TMidiPatternGUI.SetModel(AModel: THybridPersistentModel);
begin
  FModel := TMidiPattern(AModel);
end;


procedure TMidiPatternGUI.DragOver(Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
begin
  inherited DragOver(Source, X, Y, State, Accept);

  Accept := True;
end;

// Pattern has moved location inside or outside of track
procedure TMidiPatternGUI.MyEndDrag(Sender, Target: TObject; X, Y: Integer);
var
  P:Tpoint;
  C: TControl;
begin
  C := FindDragTarget(P, False);
  if Assigned(C) then
  begin
    GetCursorPos(P);
    C.DragDrop(Self, X, Y);
  end;
end;


function TMidiPatternGUI.GetDragImages: TDragImageList;
begin
  Result := inherited GetDragImages;
  if Assigned(bmp) then
  begin
    if not Assigned(Result) then
      Result := TDragImageList.Create(nil);

    Result.Clear;
    Result.Height := Height;
    Result.Width := Width;
    Result.Add(bmp, nil);
    Result.SetDragImage(0, Width div 2, Height div 2);
  end;
end;

procedure TMidiPatternGUI.Invalidate;
begin
  inherited Invalidate;
end;

procedure TMidiPatternGUI.Update(Subject: THybridPersistentModel);
begin
  DBLog('start TPatternGUI.Update');

  Position := TMidiPattern(Subject).Position;
  PatternLength := TMidiPattern(Subject).LoopEnd.Value;  //todo Use global patternlength
  Scheduled := TMidiPattern(Subject).Scheduled;
  Playing := TMidiPattern(Subject).Playing;
//  PatternControls.RealBPM := Model.WavePattern.RealBPM;
//  Text := ExtractFileName(TPattern(Subject).WavePattern.SampleFileName);

  DBLog('end TPatternGUI.Update');
end;

{ TCreateGUICommand }

procedure TMidiPatternGUI.Connect;
begin
  DBLog('start TPatternGUI.Connect');


  DBLog('end TPatternGUI.Connect');
end;

procedure TMidiPatternGUI.Disconnect;
begin
  DBLog('start TPatternGUI.Disconnect');


  DBLog('end TPatternGUI.Disconnect');
end;

initialization
  RegisterClass(TMidiPatternGUI);

end.
