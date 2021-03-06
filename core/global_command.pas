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

  global_command.pas
}

unit global_command;

{
  This unit implements the base classes for unlimitied persistent undo/redo
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ContNrs, global, globalconst, ExtCtrls, utils;

const
  DIV_BY_128 = 1 / 128;

type
  TQueueStatus = (qsExecutingCommands, qsWaitForMidiBind, qsFinishedMidiBind);

  { TCommand }

  TCommand = class(TObject)
  private
    FObjectIdList: TStringList;
    FMemento: TObjectList;
    FObjectOwner: string;
    FObjectID: string;
    FPersist: Boolean;
    FMidiLearn: Boolean;
  protected
    procedure DoExecute; virtual; abstract;
    procedure DoRollback; virtual;
  public
    constructor Create(AObjectID: string);
    destructor Destroy; override;

    procedure Initialize; virtual;
    procedure Finalize; virtual;

    procedure Execute;
    procedure Rollback; // Reverse effect of Execute

    property ObjectIdList : TStringList read FObjectIdList write FObjectIdList;
    property Memento: TObjectList read FMemento write FMemento;
    property ObjectOwner: string read FObjectOwner write FObjectOwner;
    property ObjectID: string read FObjectID write FObjectID;
    property Persist: Boolean read FPersist write FPersist default True;
    property MidiLearn: Boolean read FMidiLearn write FMidiLearn;
  end;

  TMidiMap = class
    ObjectID: string;
    ObjectOwnerID: string;
    Lowest: single;
    Highest: single;
    Parameter: Integer;
    Scale: single;
  end;

  PMidiMap = ^TMidiMap;

  { TMidiMappingTable }

  TMidiMappingTable = class(TStringList)
  public
    function AddMapping(AMidiCode: string; AObjectId: string;
      AObjectOwnerId: string; AParameter: Integer;
      ALow: single; AHigh: single): Boolean;
    function DeleteMapping(AMidiCode: string): Boolean;
  end;

  TMidiCallback = procedure(var AStatus: string) of object;

  { TCommandQueue }

  TCommandQueue = class(TObjectQueue)
  private
    FCommandQueue: TObjectQueue;
    FQueueStatus: TQueueStatus;
    FMidiMappingTable: TMidiMappingTable;
    FCurrentCommand: TCommand;
    FMidiCallback: TMidiCallback;
  public
    constructor Create;
    destructor Destroy; override;

    procedure ExecuteCommandQueue;
    procedure PushCommand(AObject: TObject);
    function PopCommand: TObject;
    property CurrentCommand: TCommand read FCurrentCommand write FCurrentCommand;
    property CommandQueue: TObjectQueue read FCommandQueue write FCommandQueue;
    property QueueStatus: TQueueStatus read FQueueStatus write FQueueStatus;
    property MidiMappingTable: TMidiMappingTable read FMidiMappingTable write FMidiMappingTable;
    property MidiCallback: TMidiCallback read FMidiCallback write FMidiCallback;
  end;

  { TMidiDataList }

  TMidiDataList = class(TList)
  private
    FLastIndex: Integer;
    FIndex: Integer;
  public
    function FrameFirstIndex(ALocation: Integer): Integer;
    function FrameLastIndex(ALocation: Integer): Integer;
    function CurrentMidiData: TMidiData;
    procedure Next;
    procedure First;
    function Eof: Boolean;

    procedure IndexList;

    property LastIndex: Integer read FLastIndex write FLastIndex;
    property Index: Integer read FIndex write FIndex;
  protected
  end;

  TValue = class
    Value: Single;
  end;

  { TAutomationCache }

  TAutomationCache = class
  private
    FObjectList: TStringList;
    procedure DeleteAutomationCache(FObjectId: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddAutomationCache(FObjectId: string);
    function ValueOfObjectId(FObjectId: string): Single;
  end;


const
  DEFAULT_MIDIBUFFER_SIZE = 1000;

type
  { TMidiBuffer }

  TMidiBuffer = class
  private
    FLength: Integer;
    FReadIndex: Integer;
    FBuffer: array[0..Pred(DEFAULT_MIDIBUFFER_SIZE)] of TMidiEvent;

    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Reset;
    procedure WriteEvent(AMidiData: TMidiData; AOffsetInBuffer: Integer);
    function ReadEvent: TMidiEvent;
    function Eof: Boolean;
    procedure Seek(APosition: Integer);
    property Count: Integer read GetCount;
  end;

var
  GCommandQueue: TCommandQueue;
  GHistoryQueue: TObjectList;
  GHistoryIndex: Integer;

implementation

uses
  pattern, sampler;

{ TAutomationCache }

constructor TAutomationCache.Create;
begin
  FObjectList := TStringList.Create;
end;

destructor TAutomationCache.Destroy;
var
  lIndex: Integer;
begin
  for lIndex := 0 to Pred(FObjectList.Count) do
  begin
    FObjectList.Objects[lIndex].Free;
  end;
  FObjectList.Free;

  inherited Destroy;
end;

procedure TAutomationCache.AddAutomationCache(FObjectId: string);
var
  lValue: TValue;
begin
  if FObjectList.IndexOf(FObjectId) = -1 then
  begin
    lValue := TValue.Create;
    lValue.Value := 0;
    FObjectList.AddObject(FObjectId, lValue);
  end;
end;

procedure TAutomationCache.DeleteAutomationCache(FObjectId: string);
var
  lIndex: Integer;
begin
  lIndex := FObjectList.IndexOf(FObjectId);
  if lIndex <> -1 then
  begin
    FObjectList.Objects[lIndex].Free;
    FObjectList.Delete(lIndex);
  end;
end;

function TAutomationCache.ValueOfObjectId(FObjectId: string): Single;
var
  lIndex: Integer;
begin
  lIndex := FObjectList.IndexOf(FObjectId);
  Result := TValue(FObjectList.Objects[lIndex]).Value;
end;

{ TMidiMappingTable }

function TMidiMappingTable.AddMapping(AMidiCode: string; AObjectId: string;
  AObjectOwnerId: string; AParameter: Integer; ALow: single; AHigh: single): Boolean;
var
  lMidiMap: TMidiMap;
begin
  lMidiMap := TMidiMap.Create;
  lMidiMap.ObjectID := AObjectId;
  lMidiMap.ObjectOwnerID := AObjectOwnerId;
  lMidiMap.Parameter := AParameter;
  lMidiMap.Lowest := ALow;
  lMidiMap.Highest := AHigh;
  lMidiMap.Scale := (AHigh - ALow) * DIV_BY_128;
  Self.AddObject(AMidiCode, lMidiMap);
end;

function TMidiMappingTable.DeleteMapping(AMidiCode: string): Boolean;
var
  lIndex: Integer;
begin
  lIndex := Self.IndexOf(AMidiCode);
  if lIndex <> -1 then
  begin
    Self.Objects[lIndex].Free;
    Self.Delete(lIndex);
  end;
end;

{ TMidiBuffer }

function TMidiBuffer.GetCount: Integer;
begin
  Result := FLength;
end;

constructor TMidiBuffer.Create;
var
  lIndex: Integer;
begin
  inherited Create;

  for lIndex := 0 to Pred(DEFAULT_MIDIBUFFER_SIZE) do
  begin
    FBuffer[lIndex] := TMidiEvent.Create;
  end;

  FReadIndex := 0;
  FLength := 0;
end;

destructor TMidiBuffer.Destroy;
var
  lIndex: Integer;
begin
  for lIndex := 0 to Pred(DEFAULT_MIDIBUFFER_SIZE) do
  begin
    FBuffer[lIndex].Free;
  end;

  inherited Destroy;
end;

{
  Resets buffer indexes but does not clear it as it get overwritten anyway
}
procedure TMidiBuffer.Reset;
begin
  FLength := 0;
  FReadIndex := 0;
end;

procedure TMidiBuffer.WriteEvent(AMidiData: TMidiData; AOffsetInBuffer: Integer);
begin

  if FLength < Pred(DEFAULT_MIDIBUFFER_SIZE) then
  begin
    FBuffer[FLength].RelativeOffset := AOffsetInBuffer;

    FBuffer[FLength].DataValue1 := AMidiData.DataValue1;
    FBuffer[FLength].DataValue2 := AMidiData.DataValue2;
    FBuffer[FLength].DataType := AMidiData.DataType;
    FBuffer[FLength].MidiChannel := AMidiData.MidiChannel;
    FBuffer[FLength].Length := AMidiData.Length;

    Inc(FLength);
  end;

end;

function TMidiBuffer.ReadEvent: TMidiEvent;
begin
  if FReadIndex < FLength then
  begin
    Result := FBuffer[FReadIndex];

    Inc(FReadIndex);
  end;
end;

function TMidiBuffer.Eof: Boolean;
begin
  Result := (FReadIndex >= FLength);
end;

procedure TMidiBuffer.Seek(APosition: Integer);
begin
  FReadIndex := APosition;
end;

{ TCommand }

procedure TCommand.DoRollback;
begin
  //
end;

procedure TCommand.Initialize;
begin
  // Virtual base method placeholder
end;

procedure TCommand.Finalize;
begin
  // Virtual base method placeholder
end;

constructor TCommand.Create(AObjectID: string);
begin
  FObjectOwner := AObjectID;
  FObjectIdList := TStringList.Create;
  FMemento := TObjectList.Create(True);
  FPersist := True;
  FMidiLearn := False;
end;

destructor TCommand.Destroy;
begin
  FObjectIdList.Free;
  FMemento.Free;

  inherited Destroy;
end;

procedure TCommand.Execute;
begin
  DoExecute;
end;

procedure TCommand.Rollback;
begin
  DoRollback;
end;

{ TCommandQueue }

constructor TCommandQueue.Create;
begin
  FCommandQueue := TObjectQueue.Create;
  FMidiMappingTable := TMidiMappingTable.Create;
  FQueueStatus := qsExecutingCommands;
end;

destructor TCommandQueue.Destroy;
begin
  FCommandQueue.Free;
  FMidiMappingTable.Free;

  inherited Destroy;
end;

procedure TCommandQueue.ExecuteCommandQueue;
var
  lCommand: TCommand;
  lStatus: string;
begin
  //while FCommandQueue.Count > 0 do
  begin
    try
      lCommand := TCommand(FCommandQueue.Pop);

      // In midi-learn mode
      if lCommand.MidiLearn then
      begin

        // What class is sending the parameter
        if lCommand is TSampleParameterCommand then
        begin
          // Make command visible to others
          FCurrentCommand := lCommand;

          if Assigned(FMidiCallback) then
          begin
            // Get last midicontroller
            FMidiCallback(lStatus);

            // Bind the two
            FMidiMappingTable.AddMapping(
              lStatus,
              lCommand.FObjectID,
              lCommand.ObjectOwner,
              Integer(TSampleParameterCommand(lCommand).Parameter),
              0,
              1);

            // Command is not used in mapping mode
            lCommand.Free;
          end;
        end;
      end
      else
      begin
        lCommand.Initialize;
        lCommand.Execute;
        lCommand.Finalize;

        if lCommand.Persist then
        begin
          GHistoryQueue.Add(lCommand);
          Inc(GHistoryIndex);
        end
        else
        begin
          lCommand.Free;
        end;
      end;

    except
      on e: exception do
      begin
        DBLog(Format('Failed command execute: %s : %s : %s',
          [lCommand.ClassName, DumpExceptionCallStack(e), DumpCallStack]));
        lCommand.Free;
      end;
    end;
  end;
end;

procedure TCommandQueue.PushCommand(AObject: TObject);
begin
  if Assigned(CommandQueue) then
  begin
    try
      CommandQueue.Push(AObject);

      ExecuteCommandQueue;
    except
      on e: Exception do
      begin
        DBLog('CommandQueue error: ' + e.Message);
        if Assigned(AObject) then
        begin
          AObject.Free;
        end;
      end;
    end;
  end;
end;

function TCommandQueue.PopCommand: TObject;
begin
  if Assigned(CommandQueue) then
  begin
    Result := CommandQueue.Pop;
  end;
end;


{ TMidiDataList }

function SortOnLocation(Item1, Item2: Pointer): Integer;
begin
  if (TMidiData(Item1).Location < TMidiData(Item2).Location) then
  begin
    result := -1
  end
  else
  begin
    if (TMidiData(Item1).Location > TMidiData(Item2).Location) then
      result := 1
    else
      result := 0;
  end;
end;

{
  Return index of first element within window
}
function TMidiDataList.FrameFirstIndex(ALocation: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;

  for i := 0 to Pred(Count) do
  begin
    if TMidiData(Items[i]).Location >= ALocation then
    begin
      Result := i;
      break;
    end;
  end;
end;

{
  Return index of last element within window
}
function TMidiDataList.FrameLastIndex(ALocation: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;

  for i := Pred(Count) downto 0 do
  begin
    if TMidiData(Items[i]).Location < ALocation then
    begin
      Result := i;
      break;
    end;
  end;
end;

function TMidiDataList.CurrentMidiData: TMidiData;
begin
  if FIndex < Count then
  begin
    Result := TMidiData(Items[FIndex]);
  end
  else
    Result := TMidiData(self.Last)
end;

procedure TMidiDataList.Next;
begin
//  if FIndex < Pred(Count) then
  begin
    FIndex := FIndex + 1;
  end;
end;

function TMidiDataList.Eof: Boolean;
begin
  Result := (FIndex >= Count);
end;

{
  This method sorts the list on location starting low ending high
  After that it will also be linked into a linked list
}
procedure TMidiDataList.IndexList;
var
  i: Integer;
begin
  Sort(@SortOnLocation);

  for i := 0 to Pred(Count) do
  begin
    if i = Pred(Count) then
    begin
      TMidiData(Items[i]).Next := nil;
    end
    else
    begin
      TMidiData(Items[i]).Next := TMidiData(Items[i + 1]);
    end;
  end;
end;

procedure TMidiDataList.First;
begin
  FIndex := 0;
end;


initialization
  GCommandQueue:= TCommandQueue.Create;

  GHistoryQueue:= TObjectList.Create;
  GHistoryIndex:= -1;

finalization
  GHistoryQueue.Free;
  GCommandQueue.Free;


end.

