(*
MIT License

Copyright (c) 2026 by.LaoZhang qq600585

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*)
{ ******************************************************************************
  * Z.LinearAction - Linear Action Execution Engine
  *
  * This unit provides a hierarchical, state-driven framework for executing
  * sequences of actions in a linear (sequential) manner. It is designed for
  * game logic, animation sequences, story flow control, and any scenario
  * requiring ordered execution of discrete steps.
  *
  * Architecture (Three-Layer Structure):
  *   1. TLAction (Base Action):
  *      The fundamental unit of execution. Each action has a lifecycle
  *      (Run ¡ú Progress ¡ú Over/Stop) and maintains its own execution state.
  *      Custom actions are created by subclassing TLAction and overriding
  *      the Progress method.
  *
  *   2. TLActionList (Action Sequence):
  *      Manages a linear list of TLAction instances. Actions are executed
  *      sequentially: when one action completes (Over), the next action
  *      in the list begins. A TCadencer timer drives the progress of the
  *      currently active action.
  *
  *   3. TLAction_Linear (Linear Executor):
  *      The top-level container that manages a sequence of TLActionList
  *      instances. It provides an additional level of nesting, allowing
  *      complex scripts to be composed of multiple action lists executed
  *      in order.
  *
  * State Machine:
  *   Each action goes through the following states:
  *     - asPlaying: The action is actively executing.
  *     - asPause:   The action is paused (still in asPlaying, but not
  *                  progressing).
  *     - asStop:    The action has been forcibly terminated.
  *     - asOver:    The action has completed normally.
  *
  * Usage:
  *   1. Subclass TLAction to implement custom behavior.
  *   2. Create a TLActionList and add actions using the Add method.
  *   3. Call Run() to start the sequence.
  *   4. Call Progress(deltaTime) repeatedly to advance execution.
  *   5. Use Over() to signal normal completion, or Stop() to abort.
  *
  * The framework also supports automatic timing via TCadencer when the
  * parameterless Progress() method is called.
  ****************************************************************************** }
unit Z.LinearAction;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses
{$IFDEF FPC}
  Z.FPC.GenericList,
{$ENDIF FPC}
  Z.Core, Z.Status, Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib, Z.Cadencer;

type
  {
    TCoreActionState enumerates the possible execution states of an action.
    - asPlaying: The action is active and progressing.
    - asPause:   The action is paused (remains in asPlaying but progress is
                 suspended).
    - asStop:    The action has been stopped (terminated prematurely).
    - asOver:    The action has completed normally.
  }
  TCoreActionState = (asPlaying, asPause, asStop, asOver);

  {
    TCoreActionStates is a set of TCoreActionState, allowing an action to be
    in multiple states simultaneously (e.g., asPlaying and asPause).
  }
  TCoreActionStates = set of TCoreActionState;

  { Forward declarations for mutually dependent classes }
  TLAction = class;
  TLActionList = class;
  TLAction_Linear = class;

  {
    TLAction is the abstract base class for all actions in the linear action
    framework. It defines the lifecycle methods and state management for a
    single executable unit.

    To create a custom action, subclass TLAction and override the Progress
    method. The Run, Over, Stop, and Pause methods can also be overridden
    to implement custom state transition logic.

    The action maintains its own State set, which is used by the parent
    TLActionList to determine when to advance to the next action.
  }
  TLAction = class(TCore_Object_Intermediate)
  private
    State: TCoreActionStates;   { Current execution state of this action }
  public
    { The TLActionList that owns this action. }
    Owner: TLActionList;

    {
      Constructs a new action with the specified owner list.
      @param Owner_ The TLActionList that will manage this action.
    }
    constructor Create(Owner_: TLActionList); virtual;

    destructor Destroy; override;

    {
      Starts the action. This method is called by the parent TLActionList
      when the action becomes active. The default implementation sets the
      state to asPlaying.
    }
    procedure Run(); virtual;

    {
      Signals that the action has completed normally. This method is called
      by the action itself when its work is done. The default implementation
      transitions from asPlaying to asOver.
    }
    procedure Over(); virtual;

    {
      Alias for Over(). Marks the action as completed.
    }
    procedure Done();

    {
      Stops the action prematurely. This method can be called by external
      code to abort the action. The default implementation transitions
      from asPlaying to asStop.
    }
    procedure Stop(); virtual;

    {
      Pauses the action. When paused, the action remains in asPlaying but
      will not progress. The default implementation adds asPause to the
      state set.
    }
    procedure Pause(); virtual;

    {
      Updates the action's internal state. This method is called repeatedly
      by the parent TLActionList with the elapsed time delta. Subclasses
      should override this method to implement their core logic.

      The default implementation does nothing.

      @param deltaTime The time elapsed since the last update (in seconds).
    }
    procedure Progress(deltaTime: Double); virtual;
  end;

  {
    TLActionClass is a meta-class type for TLAction, used for dynamic
    instantiation of actions via TLActionList.Add(ActionClass_).
  }
  TLActionClass = class of TLAction;

  {
    TLActionList_Decl is a generic list type for storing TLAction instances.
  }
  TLActionList_Decl = TGenericsList<TLAction>;

  {
    TLActionList manages a sequential list of TLAction instances. Actions
    are executed in order: when the current action transitions to asOver,
    the next action in the list is automatically started.

    Each TLActionList can optionally be owned by a TLAction_Linear, which
    allows multiple lists to be chained together.

    The list is driven by a TCadencer timer, which can be used to call
    Progress automatically, or Progress can be called manually with a
    deltaTime parameter.
  }
  TLActionList = class(TCore_Object_Intermediate)
  protected
    FSequenceList: TLActionList_Decl;    { The list of actions to execute }
    FIndex: Integer;                     { Index of the currently executing action }
    FLast: TLAction;                     { The currently executing action }
    FCadender: TCadencer;                { Timer for driving progress }
    procedure Do_CadencerProgress(Sender: TObject; const deltaTime, newTime: Double);
  public
    { The TLAction_Linear that owns this action list (may be nil). }
    Owner: TLAction_Linear;

    constructor Create(Owner_: TLAction_Linear);
    destructor Destroy; override;

    { Removes all actions from the list. }
    procedure Clear;

    {
      Adds a new action to the end of the list. The action is instantiated
      using the provided action class.
      @param ActionClass_ The meta-class of the action to create.
      @return The newly created action instance.
    }
    function Add(ActionClass_: TLActionClass): TLAction;

    {
      Starts execution of the action list. The first action in the list is
      activated, and its Run method is called.
    }
    procedure Run();

    {
      Signals that the entire action list has completed normally. This method
      is typically called by the owner TLAction_Linear when the list finishes.
    }
    procedure Over();

    {
      Stops execution of the entire action list. The currently executing
      action is stopped, and the list is reset.
    }
    procedure Stop();

    {
      Returns True if the action list has completed execution (all actions
      have reached the asOver state).
    }
    function IsOver(): Boolean;

    {
      Returns True if the action list has been stopped (the Stop method
      was called).
    }
    function IsStop(): Boolean;

    { Returns the currently executing action, or nil if none. }
    property Last: TLAction read FLast;

    {
      Drives the execution of the action list by advancing the current
      action by the specified delta time. This method should be called
      repeatedly in the main loop.

      @param deltaTime The time elapsed since the last update (in seconds).
    }
    procedure Progress(deltaTime: Double); overload;

    {
      Drives the execution of the action list using an internal TCadencer
      timer. The timer is automatically created and started on the first
      call. Subsequent calls advance the timer and trigger the progress.

      This is useful when the action list is not being driven by an external
      game loop.
    }
    procedure Progress; overload;

    { Returns the underlying list of actions. }
    property List: TLActionList_Decl read FSequenceList;
  end;

  {
    TLActionList_Decl_List_Decl is a generic list type for storing
    TLActionList instances.
  }
  TLActionList_Decl_List_Decl = TGenericsList<TLActionList>;

  {
    TLAction_Linear is the top-level container that manages a sequence of
    TLActionList instances. It provides an additional nesting level, allowing
    complex scripts to be composed of multiple action lists executed in order.

    When a TLActionList completes (all its actions are Over), the next
    TLActionList in the sequence is automatically started.

    Like TLActionList, TLAction_Linear can be driven either manually via
    Progress(deltaTime) or automatically via the parameterless Progress()
    method with an internal TCadencer.
  }
  TLAction_Linear = class(TCore_Object_Intermediate)
  protected
    FLinear_List: TLActionList_Decl_List_Decl;   { List of action lists }
    FIndex: Integer;                             { Index of the current action list }
    FLast: TLActionList;                         { The currently active action list }
    FCadender: TCadencer;                        { Timer for driving progress }
    procedure Do_CadencerProgress(Sender: TObject; const deltaTime, newTime: Double);
  public
    constructor Create();
    destructor Destroy; override;

    { Removes all action lists from the executor. }
    procedure Clear;

    {
      Adds a new empty TLActionList to the end of the sequence.
      @return The newly created action list, which can then be populated
              with actions.
    }
    function Add: TLActionList;

    {
      Starts execution of the sequence. The first TLActionList in the
      sequence is activated, and its Run method is called.
    }
    procedure Run();

    {
      Stops execution of the entire sequence. All action lists are stopped
      and the sequence is reset.
    }
    procedure Stop();

    {
      Signals that the current TLActionList has completed. This method is
      called internally when a list finishes. If more lists remain, the next
      one is started; otherwise, the sequence clears itself.
    }
    procedure Over();

    { Returns the currently active action list, or nil if none. }
    property Last: TLActionList read FLast;

    {
      Drives the execution of the sequence by advancing the current action
      list by the specified delta time.

      @param deltaTime The time elapsed since the last update (in seconds).
    }
    procedure Progress(deltaTime: Double); overload;

    {
      Drives the execution of the sequence using an internal TCadencer timer.
      The timer is automatically created and started on the first call.
    }
    procedure Progress; overload;

    { Returns the underlying list of action lists. }
    property List: TLActionList_Decl_List_Decl read FLinear_List;

    {
      Unit test procedure that creates a TLActionList with 10 actions,
      runs them, and drives progress until completion.
    }
    class procedure Test();
  end;

implementation

constructor TLAction.Create(Owner_: TLActionList);
begin
  inherited Create;
  Owner := Owner_;
  State := [];
end;

destructor TLAction.Destroy;
begin
  inherited Destroy;
end;

procedure TLAction.Run;
begin
  State := [asPlaying];
end;

procedure TLAction.Over;
begin
  if asPlaying in State then
      State := [asOver];
end;

procedure TLAction.Done;
begin
  Over();
end;

procedure TLAction.Stop;
begin
  if asPlaying in State then
      State := [asStop];
end;

procedure TLAction.Pause;
begin
  if asPlaying in State then
      State := [asPlaying, asPause];
end;

procedure TLAction.Progress(deltaTime: Double);
begin

end;

procedure TLActionList.Do_CadencerProgress(Sender: TObject; const deltaTime, newTime: Double);
begin
  Progress(deltaTime);
end;

constructor TLActionList.Create(Owner_: TLAction_Linear);
begin
  inherited Create;
  FSequenceList := TLActionList_Decl.Create;
  FIndex := -1;
  FLast := nil;
  FCadender := nil;
  Owner := Owner_;
end;

destructor TLActionList.Destroy;
begin
  Clear;
  DisposeObjectAndNil(FCadender);
  DisposeObjectAndNil(FSequenceList);
  inherited Destroy;
end;

procedure TLActionList.Clear;
var
  i: Integer;
begin
  for i := FSequenceList.Count - 1 downto 0 do
      DisposeObject(FSequenceList[i]);
  FSequenceList.Clear;
end;

function TLActionList.Add(ActionClass_: TLActionClass): TLAction;
begin
  Result := ActionClass_.Create(Self);
  FSequenceList.Add(Result);
end;

procedure TLActionList.Run();
begin
  if FSequenceList.Count > 0 then
    begin
      FIndex := 0;
      FLast := FSequenceList[FIndex] as TLAction;
    end
  else
    begin
      FIndex := -1;
      FLast := nil;
    end;
end;

procedure TLActionList.Over;
begin
  if FLast <> nil then
    begin
      FIndex := FSequenceList.Count;
      if Owner <> nil then
          Owner.Over;
    end;
end;

procedure TLActionList.Stop;
begin
  if FLast <> nil then
      FIndex := -1;
end;

function TLActionList.IsOver: Boolean;
begin
  Result := FIndex >= FSequenceList.Count;
end;

function TLActionList.IsStop: Boolean;
begin
  Result := FIndex < 0;
end;

procedure TLActionList.Progress(deltaTime: Double);
begin
  if (FIndex < 0) or (FIndex >= FSequenceList.Count) then
      Exit;

  FLast := FSequenceList[FIndex];

  if FLast.State = [] then
    begin
      FLast.Run;
      Exit;
    end;

  if asPlaying in FLast.State then
    begin
      FLast.Progress(deltaTime);
      Exit;
    end;

  if asStop in FLast.State then
    begin
      FIndex := -1;
      if Owner <> nil then
          Owner.Stop;
      Exit;
    end;

  if asOver in FLast.State then
    begin
      inc(FIndex);
      if (FIndex >= FSequenceList.Count) and (Owner <> nil) then
          Owner.Over;
      Exit;
    end;
end;

procedure TLActionList.Progress;
begin
  if FCadender = nil then
    begin
      FCadender := TCadencer.Create;
      FCadender.OnProgress := Do_CadencerProgress;
    end;
  FCadender.Progress;
end;

procedure TLAction_Linear.Do_CadencerProgress(Sender: TObject; const deltaTime, newTime: Double);
begin
  Progress(deltaTime);
end;

constructor TLAction_Linear.Create();
begin
  inherited Create;
  FLinear_List := TLActionList_Decl_List_Decl.Create;
  FIndex := -1;
  FLast := nil;
  FCadender := nil;
end;

destructor TLAction_Linear.Destroy;
begin
  Clear;
  DisposeObjectAndNil(FCadender);
  DisposeObjectAndNil(FLinear_List);
  inherited Destroy;
end;

procedure TLAction_Linear.Clear;
var
  i: Integer;
begin
  for i := FLinear_List.Count - 1 downto 0 do
      DisposeObject(FLinear_List[i]);
  FLinear_List.Clear;
  FIndex := -1;
  FLast := nil;
end;

function TLAction_Linear.Add: TLActionList;
begin
  Result := TLActionList.Create(Self);
  FLinear_List.Add(Result);
end;

procedure TLAction_Linear.Run;
begin
  if FLinear_List.Count > 0 then
    begin
      FIndex := 0;
      FLast := FLinear_List[FIndex];
    end
  else
    begin
      FIndex := -1;
      FLast := nil;
    end;
end;

procedure TLAction_Linear.Stop;
begin
  Clear;
end;

procedure TLAction_Linear.Over;
begin
  inc(FIndex);
  if FIndex < FLinear_List.Count then
    begin
      FLast := FLinear_List[FIndex];
    end
  else
    begin
      Clear;
    end;
end;

procedure TLAction_Linear.Progress(deltaTime: Double);
begin
  if FLast <> nil then
      FLast.Progress(deltaTime);
end;

procedure TLAction_Linear.Progress;
begin
  if FCadender = nil then
    begin
      FCadender := TCadencer.Create;
      FCadender.OnProgress := Do_CadencerProgress;
    end;
  FCadender.Progress;
end;

class procedure TLAction_Linear.Test();
var
  L: TLActionList;
  i: Integer;
begin
  L := TLActionList.Create(nil);
  for i := 1 to 10 do
      L.Add(TLAction);
  L.Run;
  while True do
    begin
      L.Progress(0.1);
      L.Last.Over;
      if L.IsOver or L.IsStop then
          Break;
    end;
  DisposeObject(L);
end;

end.
 
