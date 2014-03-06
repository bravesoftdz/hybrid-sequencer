unit stretcher;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, utils, math, globalconst, uCrossCorrelateFFT;

type
  { TSliceLooper }

  TSliceLooper = class
  private
    FPitch: Single;
    FSliceEnd: Single;
    FSliceStart: Single;
    FCursor: Single;
    FSliceHalfLength: Integer;
    procedure SetSliceEnd(AValue: Single);
    procedure SetSliceStart(AValue: Single);
  public
    function Process: Single;
    property SliceStart: Single read FSliceStart write SetSliceStart;
    property SliceEnd: Single read FSliceEnd write SetSliceEnd;
    property Cursor: Single read FCursor write FCursor;
    property Pitch: Single read FPitch write FPitch;
  end;

  { TStretcher }

  TStretcher = class
  private
    FCrossCorrelate: TCrossCorrelate;
    FPitch: Single;
    FSampleScale: Single;
    FLastSliceIndex: Integer;
    FSliceList: TObjectList;
    FSliceStartLocation: single;
    FSliceEndLocation: single;
    FSliceHalfLength: Integer;
    FSliceLastCounter: Single;

    FSliceMainCursor: Single;
    FSliceOverlapCursor: Single;
    FOverlapFadeOut: Single;
    FOverlapFadeIn: Single;
    FOverlapFadeAdder: Single;

    FSliceLoopModulo: Integer;
    FSliceFadeIn: Single;
    FSliceFadeOut: Single;
    FSliceLooper: TSliceLooper;

    FOverlapTrigger: Boolean;
    FOverlapping: Boolean;
    FOverlapLengthMs: Integer;
    FOverlapLength: Integer;
    FSeekwindowMs: Integer;
    FSeekwindow: Integer;
    FSequencewindowMs: Integer;
    FSequencewindow: Integer;

    FSamplerate: Integer;

    FInterpolationAlgorithm: TInterpolationAlgorithm;
    procedure GetSample(
      ACursor: Single;
      ASourceBuffer: PSingle;
      var ALeftValue: Single;
      var ARightValue: Single;
      AChannelCount: Integer);
    procedure SetOverlapLengthMs(AValue: Integer);
    procedure SetSeekwindowMs(AValue: Integer);
    procedure SetSequencewindowMs(AValue: Integer);
  public
    constructor Create(ASamplerate: Integer);
    destructor Destroy; override;
    procedure Process(
      AStartIndex: Integer;
      var ASampleCursor: Single;
      var ASliceCounter: Single;
      ASourceBuffer: PSingle;
      ATargetBuffer: PSingle;
      AFrameIndex: Integer;
      AChannelCount: Integer);
    property InterpolationAlgorithm: TInterpolationAlgorithm read FInterpolationAlgorithm write FInterpolationAlgorithm;
    property SliceList: TObjectList read FSliceList write FSliceList;
    property Pitch: Single read FPitch write FPitch;
    property SampleScale: Single read FSampleScale write FSampleScale;
    property OverlapLengthMs: Integer write SetOverlapLengthMs;
    property SeekwindowMs: Integer write SetSeekwindowMs;
    property SequencewindowMs: Integer write SetSequencewindowMs;
  end;


implementation

{ TSliceLooper }

procedure TSliceLooper.SetSliceEnd(AValue: Single);
begin
  FSliceEnd := AValue;

  FSliceHalfLength := Round(FSliceEnd - FSliceStart) div 2;
end;

procedure TSliceLooper.SetSliceStart(AValue: Single);
begin
  FSliceStart := AValue;

  FSliceHalfLength := Round(FSliceEnd - FSliceStart) div 2;
end;

function TSliceLooper.Process: Single;
var
  lSliceLoopModulo: Integer;
begin
  // Ran past end of slice so loop a part of the previous section
  if FSliceHalfLength <> 0 then
  begin
    lSliceLoopModulo := Round(FCursor - FSliceEnd) mod FSliceHalfLength;
    if Odd(Round(FCursor - FSliceEnd) div FSliceHalfLength) then
    begin
      Result := Round(FSliceEnd - FSliceHalfLength) + lSliceLoopModulo;
    end
    else
    begin
      Result := Round(FSliceEnd) - lSliceLoopModulo;
    end;
  end;
  FCursor := FCursor + FPitch;
end;

{ TStretcher }

constructor TStretcher.Create(ASamplerate: Integer);
begin
  FSamplerate := ASamplerate;

  FSliceLooper := TSliceLooper.Create;
  FCrossCorrelate := TCrossCorrelate.Create(ASamplerate);

  FOverlapping := False;
  FOverlapTrigger := False;
  FLastSliceIndex := -1;
end;

destructor TStretcher.Destroy;
begin
  FSliceLooper.Free;

  inherited Destroy;
end;

procedure TStretcher.GetSample(
  ACursor: Single;
  ASourceBuffer: PSingle;
  var ALeftValue: Single;
  var ARightValue: Single;
  AChannelCount: Integer);
var
  lFracPosition: Single;
  lBufferOffset: integer;
begin
  lBufferOffset := Round(ACursor * AChannelCount);

  case FInterpolationAlgorithm of
    iaHermite:
    begin
      lFracPosition := Frac(ACursor);

      if AChannelCount = 1 then
      begin
        ALeftValue := hermite4(
          lFracPosition,
          ifthen(lBufferOffset <= 1, 0, ASourceBuffer[lBufferOffset - 1]),
          ASourceBuffer[lBufferOffset],
          ASourceBuffer[lBufferOffset + 1],
          ASourceBuffer[lBufferOffset + 2]);

        ARightValue := ALeftValue;
      end
      else
      begin
        ALeftValue := hermite4(
          lFracPosition,
          ifthen(lBufferOffset <= 1, 0, ASourceBuffer[lBufferOffset - 2]),
          ASourceBuffer[lBufferOffset],
          ASourceBuffer[lBufferOffset + 2],
          ASourceBuffer[lBufferOffset + 4]);

        ARightValue := hermite4(
          lFracPosition,
          ifthen(lBufferOffset + 1 <= 2, 0, ASourceBuffer[lBufferOffset - 1]),
          ASourceBuffer[lBufferOffset + 1],
          ASourceBuffer[lBufferOffset + 3],
          ASourceBuffer[lBufferOffset + 5]);
      end;
    end;
    iaLinear:
    begin

    end;
    iaNone:
    begin
      if AChannelCount = 1 then
      begin
        ALeftValue := ASourceBuffer[lBufferOffset];
        ARightValue := ASourceBuffer[lBufferOffset];
      end
      else
      begin
        ALeftValue := ASourceBuffer[lBufferOffset];
        ARightValue := ASourceBuffer[lBufferOffset + 1];
      end;
    end;
  end;
end;

procedure TStretcher.SetOverlapLengthMs(AValue: Integer);
begin
  FOverlapLengthMs := AValue;

  FOverlapLength := Round(FSampleRate / (1000 / FOverlapLengthMs));
  FCrossCorrelate.OverlapLength := FOverlapLengthMs;
end;

procedure TStretcher.SetSeekwindowMs(AValue: Integer);
begin
  FSeekwindowMs := AValue;

  FSeekwindow := Round(FSampleRate / (1000 / FSeekwindowMs));
  FCrossCorrelate.SeekWindowLength := FSeekwindowMs;
end;

procedure TStretcher.SetSequencewindowMs(AValue: Integer);
begin
  FSequencewindowMs := AValue;

  FSequencewindow := Round(FSampleRate / (1000 / FSequencewindowMs));
end;

procedure TStretcher.Process(
  AStartIndex: Integer;
  var ASampleCursor: Single;
  var ASliceCounter: Single;
  ASourceBuffer: PSingle;
  ATargetBuffer: PSingle;
  AFrameIndex: Integer;
  AChannelCount: Integer);
var
  i: Integer;
  lSliceStart: TMarker;
  lSliceEnd: TMarker;
  lLeftValueMain: Single;
  lRightValueMain: Single;
  lLeftValueOverlap: Single;
  lRightValueOverlap: Single;
  lLeftValueLooper: Single;
  lRightValueLooper: Single;
  lCursor: Single;
  lLoopingCursor: Single;
  lSeekwindowOffset: Integer;
  lOffset: Integer;
  lCalculatedCursor: Single;
  lSequenceWindow: Single;
begin
  for i := AStartIndex to FSliceList.Count - 2 do
  begin
    lSliceStart := TMarker(FSliceList.Items[i]);
    lSliceEnd := TMarker(FSliceList.Items[i + 1]);

    if (ASampleCursor >= lSliceStart.Location) and (ASampleCursor < lSliceEnd.Location) then
    begin
      // Detect slice synchronize
      lSequenceWindow := {lSliceStart.Length / 2;}FSequencewindow;

      ASliceCounter := fmod(ASampleCursor - lSliceStart.Location, lSequenceWindow);

      // Jumped to next slice
      if FLastSliceIndex <> i then
      begin
        DBLog(format('FLastSliceIndex %d i %d: ', [FLastSliceIndex, i]));

        // Keep last slice looping
        FSliceLooper.SliceStart := FSliceStartLocation;
        FSliceLooper.SliceEnd := FSliceEndLocation;
        FSliceLooper.Cursor := FSliceMainCursor;
        FSliceLooper.Pitch := FPitch;

        // Start of slice
        FSliceStartLocation :=
          lSliceStart.OrigLocation +
          (lSliceStart.DecayRate * (ASampleCursor - lSliceStart.Location));

        FSliceEndLocation :=
          FSliceStartLocation +
          lSliceStart.Length * FSampleScale * lSliceStart.DecayRate;

        FSliceMainCursor := FSliceStartLocation;

        FSliceFadeOut := 1;
        FSliceFadeIn :=  0;
      end;

      FOverlapping := ASliceCounter > lSequenceWindow - FOverlapLength;
      if FOverlapping then
      begin
        if not FOverlapTrigger then
        begin
          FOverlapTrigger := True;

          // Seek in history (maybe better around or future)
          lCalculatedCursor :=
            lSliceStart.OrigLocation +
            (lSliceStart.DecayRate * (ASampleCursor - lSliceStart.Location));

          lSeekwindowOffset := Round(lCalculatedCursor - FSeekwindow);
          if lSeekwindowOffset < 0 then
          begin
            lSeekwindowOffset := 0;
          end
          else if lSeekwindowOffset + FSeekwindow > TMarker(FSliceList.Last).Location then
          begin
            lSeekwindowOffset := TMarker(FSliceList.Last).Location - FSeekwindow;
          end;

          // Crosscorrelate last played audio with audio at the real cursor
          lOffset := FCrossCorrelate.Process(
            @ASourceBuffer[Round(FSliceMainCursor)],
            @ASourceBuffer[lSeekwindowOffset],
            2);

          DBLog(format('lOffset %d lSeekwindowOffset %d FSequencewindow %d FOverlapLength %d FSeekwindow %d', [lOffset, lSeekwindowOffset, FSequencewindow, FOverlapLength, FSeekwindow]));

          // Old cursor
          FSliceOverlapCursor := FSliceMainCursor;

          // New cursor
          FSliceMainCursor := lSeekwindowOffset + lOffset;

          FOverlapFadeIn := 0;
          FOverlapFadeOut := 1;
          FOverlapFadeAdder := 1 / FOverlapLength;
        end;

        if FSliceFadeOut > 0 then
        begin
          FOverlapFadeOut := FOverlapFadeOut - FOverlapFadeAdder
        end
        else
        begin
          FOverlapFadeOut := 0;
        end;
        if FOverlapFadeIn < 1 then
        begin
          FOverlapFadeIn := FOverlapFadeIn + FOverlapFadeAdder
        end
        else
        begin
          FOverlapFadeIn := 1;
        end;
      end
      else
      begin
        FOverlapTrigger := False;
        FOverlapFadeIn := 1;
        FOverlapFadeOut := 0;
      end;

      // Increate nominal always playing at samplespeed * pitch
      FSliceMainCursor := FSliceMainCursor + Pitch;
      FSliceOverlapCursor := FSliceOverlapCursor + Pitch;

      FSliceLastCounter := ASliceCounter;

      // Get normal stream
      GetSample(FSliceMainCursor, ASourceBuffer, lLeftValueMain, lRightValueMain, AChannelCount);

      // Get overlap stream
      GetSample(FSliceOverlapCursor, ASourceBuffer, lLeftValueOverlap, lRightValueOverlap, AChannelCount);

      // Mix both streams together
      ATargetBuffer[AFrameIndex * 2] :=
        lLeftValueMain * FOverlapFadeIn
        +
        lLeftValueOverlap * FOverlapFadeOut;

      ATargetBuffer[AFrameIndex * 2 + 1] :=
        lRightValueMain * FOverlapFadeIn
        +
        lRightValueOverlap * FOverlapFadeOut;

      FLastSliceIndex := i;
      break;
    end;
  end;
end;

end.
