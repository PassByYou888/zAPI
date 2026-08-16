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
{
  Z.BulletMovementEngine – High‑speed projectile movement engine.

  This unit provides a movement engine specialised for bullets, missiles, or
  any fast‑moving projectile that follows a path with smooth rotation.
  Unlike the standard movement engine (Z.MovementEngine), this version does
  not apply speed reduction during turns (no RollMoveThreshold), making it
  suitable for high‑velocity objects where constant speed is desired.

  The engine drives an object along a series of waypoints (path) while
  smoothly rotating its heading toward the next segment. It supports two
  modes: path following and simple rotation‑in‑place. Additionally, it
  maintains a history of recent positions (step history) for trail effects,
  predictive aiming, or replay.

  The engine communicates with the host object via the
  IBulletMovementInterface callback interface, which decouples movement
  logic from the specific object type. It supports pause/resume, stop,
  and event notifications for step changes and movement completion.

  Key features:
    – Constant movement speed (no slowdown during turns).
    – Path following with smooth rotation.
    – Configurable movement and rotation speeds.
    – Step history recording with configurable maximum size.
    – Loop‑less: path ends when the last waypoint is reached.
    – Pause/Resume and Stop functionality.
    – Two operation modes:
        * bmmBulletMovementPath: follow a path of waypoints.
        * bmmStopRollAngle: rotate to a target angle without moving.
}

unit Z.BulletMovementEngine;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses
{$IFDEF FPC}
  Z.FPC.GenericList,
{$ENDIF FPC}
  Z.Core,
  Z.Geometry2D, Z.Geometry3D;

type
  {
    TBulletMovementStepData – a single waypoint for bullet movement.

    Contains the target position (2D), the desired heading angle when moving
    toward this step, and its index in the path sequence. The angle is
    computed as the direction from the previous step to this step, or from
    the current position to the first step.
  }
  TBulletMovementStepData = record
    Position: TVec2; // Target position for this step.
    Angle: TGeoFloat; // Desired heading angle (in degrees) at this step.
    Index: Integer; // Sequential index in the path.
  end;

  {
    IBulletMovementInterface – callback interface for bullet movement.

    The host object must implement these methods to provide position/angle
    access and to receive notifications about movement events. This design
    allows the engine to be reused with any projectile object (e.g., bullets,
    missiles, particles) without inheritance.
  }
  IBulletMovementInterface = interface
    { Return the current position of the bullet. }
    function GetBulletPosition: TVec2;

    { Set the current position of the bullet. }
    procedure SetBulletPosition(const Value: TVec2);

    { Return the current roll (heading) angle of the bullet. }
    function GetBulletRollAngle: TGeoFloat;

    { Set the current roll (heading) angle of the bullet. }
    procedure SetBulletRollAngle(const Value: TGeoFloat);

    { Called when the engine begins a new movement session. }
    procedure StartBulletMovement;

    { Called when the movement session completes (all steps reached). }
    procedure DoneBulletMovement;

    { Called when the engine starts rotating toward the next step's angle. }
    procedure StartBulletRoll;

    { Called when the engine finishes rotating to the target angle. }
    procedure DoneBulletRoll;

    { Called when the engine is stopped via the Stop method. }
    procedure StopBullet;

    { Called when the engine is paused. }
    procedure PauseBullet;

    { Called when the engine resumes from a paused state. }
    procedure ResumeBullet;

    {
      Called when the engine moves from one step to the next in the path.
      @param OldStep The previous waypoint data.
      @param NewStep The new waypoint data.
    }
    procedure BulletStep(OldStep, NewStep: TBulletMovementStepData);

    {
      Called each frame during movement progression.
      @param deltaTime The elapsed time since the last update.
    }
    procedure BulletProgress(deltaTime: Double);
  end;

  {
    TBulletMovementMode – the engine's operating mode.
    - bmmBulletMovementPath: follow a sequence of waypoints.
    - bmmStopRollAngle: rotate in place to a target angle.
  }
  TBulletMovementMode = (bmmBulletMovementPath, bmmStopRollAngle);

  {
    TStepHistoryData – a single recorded state for step history.

    Stores the position and angle at a given moment, typically used to create
    trail effects or for debugging.
  }
  TStepHistoryData = record
    Position: TVec2; // Position at the recorded moment.
    Angle: TGeoFloat; // Heading angle at the recorded moment.
  end;

  { A FIFO queue (order structure) for storing step history entries. }
  TBulletMovementStepHistory = TOrderStruct<TStepHistoryData>;

  {
    TBulletMovementEngine – the main projectile movement engine.

    Drives an object along a path defined by waypoints, or rotates it to a
    target angle. Unlike the standard TMovementEngine, this engine does not
    reduce speed during turns, making it ideal for bullets and other
    high‑speed projectiles. It also maintains a configurable step history
    for trail rendering or trajectory analysis.

    The engine uses the callback interface to read/write position and angle,
    and to notify the host of events. The Progress method should be called
    each frame with the elapsed delta time.
  }
  TBulletMovementEngine = class(TCore_Object_Intermediate)
  private
    FOnInterface: IBulletMovementInterface; // Callback interface to the host object.
    FSteps: array of TBulletMovementStepData; // Array of waypoints defining the path.
    FActive: Boolean; // True if the engine is currently running.
    FPause: Boolean; // True if movement is paused.
    FMoveSpeed: TGeoFloat; // Movement speed (units per second).
    FRollSpeed: TGeoFloat; // Rotation speed (degrees per second).
    FOperationMode: TBulletMovementMode; // Current operating mode.
    FMaxStepHistoryNum: Integer; // Maximum number of history entries to keep.
    FStepHistory: TBulletMovementStepHistory; // FIFO queue of recent states.
    FStopRollAngle: TGeoFloat; // Target angle for stop‑and‑rotate mode.
    FLastProgressDeltaTime: Double; // Last delta time passed to Progress.
    FCurrentPathStepTo: Integer; // Index of the next waypoint to reach.
    FFromPosition: TVec2; // Position at start of current segment.
    FToPosition: TVec2; // Destination of current segment.
    FBulletMovementDone, FRollDone: Boolean; // Flags for segment completion.
  protected
    { Returns the current position via the interface. }
    function GetPosition: TVec2;

    { Sets the current position via the interface. }
    procedure SetPosition(const Value: TVec2);

    { Returns the current roll angle via the interface. }
    function GetRollAngle: TGeoFloat;

    { Sets the current roll angle via the interface. }
    procedure SetRollAngle(const Value: TGeoFloat);

    { Returns the first waypoint in the path. Assumes FSteps is not empty. }
    function FirstStep: TBulletMovementStepData;

    { Returns the last waypoint in the path. Assumes FSteps is not empty. }
    function LastStep: TBulletMovementStepData;
  public
    constructor Create;
    destructor Destroy; override;

    {
      Start movement toward a single target position.
      The engine will rotate in place to face the target (bmmStopRollAngle mode).
      @param To_ The target position.
    }
    procedure Start(To_: TVec2); overload;

    {
      Start movement along a path defined by a list of waypoints.
      The engine will move through the points in order, rotating to face
      each segment's direction. Movement speed is constant (no turn slowdown).
      @param Paths_ A TV2L list of waypoints (must not be nil or empty).
    }
    procedure Start(Paths_: TV2L); overload;

    {
      Resume a paused movement session.
      If the engine is active and paused, it will resume.
    }
    procedure Start; overload;

    {
      Stop the current movement session immediately.
      The engine will reset all internal state and fire StopBullet.
    }
    procedure stop;

    {
      Pause the current movement session.
      The engine will stop updating but retain its state; use Start to resume.
    }
    procedure Pause;

    {
      Advance the engine by the given delta time.
      This method should be called every frame with the elapsed time since
      the last call. It updates position and angle, fires events as waypoints
      are reached, and records step history if configured.
      @param deltaTime Time elapsed since the last update (in seconds).
    }
    procedure Progress(const deltaTime: Double);

    { The callback interface used by the engine to communicate with the host. }
    property OnInterface: IBulletMovementInterface read FOnInterface write FOnInterface;

    { Current position (read/write via the interface). }
    property Position: TVec2 read GetPosition write SetPosition;

    { Current roll (heading) angle (read/write via the interface). }
    property RollAngle: TGeoFloat read GetRollAngle write SetRollAngle;

    { True if the engine is paused. }
    property IsPause: Boolean read FPause;

    { True if the engine is currently active (running). }
    property Active: Boolean read FActive;

    { Movement speed in units per second. }
    property MoveSpeed: TGeoFloat read FMoveSpeed write FMoveSpeed;

    { Rotation speed in degrees per second. }
    property RollSpeed: TGeoFloat read FRollSpeed write FRollSpeed;

    { The current operation mode (path following or angle stopping). }
    property OperationMode: TBulletMovementMode read FOperationMode write FOperationMode;

    { Position at the start of the current path segment. }
    property FromPosition: TVec2 read FFromPosition;

    { Destination position of the current path segment. }
    property ToPosition: TVec2 read FToPosition;

    { Maximum number of entries to keep in the step history. Set to 0 to disable recording. }
    property MaxStepHistoryNum: Integer read FMaxStepHistoryNum write FMaxStepHistoryNum;

    { FIFO queue containing the recorded step history. }
    property StepHistory: TBulletMovementStepHistory read FStepHistory;
  end;

implementation

function TBulletMovementEngine.GetPosition: TVec2;
begin
  Result := FOnInterface.GetBulletPosition;
end;

procedure TBulletMovementEngine.SetPosition(const Value: TVec2);
begin
  FOnInterface.SetBulletPosition(Value);
end;

function TBulletMovementEngine.GetRollAngle: TGeoFloat;
begin
  Result := FOnInterface.GetBulletRollAngle;
end;

procedure TBulletMovementEngine.SetRollAngle(const Value: TGeoFloat);
begin
  FOnInterface.SetBulletRollAngle(Value);
end;

function TBulletMovementEngine.FirstStep: TBulletMovementStepData;
begin
  Result := FSteps[0];
end;

function TBulletMovementEngine.LastStep: TBulletMovementStepData;
begin
  Result := FSteps[length(FSteps) - 1];
end;

constructor TBulletMovementEngine.Create;
begin
  inherited Create;
  SetLength(FSteps, 0);
  FOnInterface := nil;
  FActive := False;
  FPause := False;
  FMoveSpeed := 300;
  FRollSpeed := 360;
  FOperationMode := bmmBulletMovementPath;
  FMaxStepHistoryNum := 0;
  FStepHistory := TBulletMovementStepHistory.Create;
  FStopRollAngle := 0;
  FLastProgressDeltaTime := 0;
  FCurrentPathStepTo := -1;
  FFromPosition := NULLPoint;
  FToPosition := NULLPoint;
  FBulletMovementDone := False;
  FRollDone := False;
end;

destructor TBulletMovementEngine.Destroy;
begin
  DisposeObject(FStepHistory);
  SetLength(FSteps, 0);
  FOnInterface := nil;
  inherited Destroy;
end;

procedure TBulletMovementEngine.Start(To_: TVec2);
begin
  if not FActive then
    begin
      SetLength(FSteps, 0);
      FStopRollAngle := CalcAngle(Position, To_);
      FOperationMode := bmmStopRollAngle;
      FActive := True;
      FPause := False;
      FToPosition := To_;
      FOnInterface.StartBulletMovement;
    end;
end;

procedure TBulletMovementEngine.Start(Paths_: TV2L);
var
  i: Integer;
begin
  Paths_.RemoveSame;

  if not FActive then
    begin
      FCurrentPathStepTo := 0;
      FFromPosition := NULLPoint;
      FBulletMovementDone := False;
      FRollDone := False;
      FOperationMode := bmmBulletMovementPath;

      FActive := (Paths_ <> nil) and (Paths_.Count > 0) and (FOnInterface <> nil);
      if FActive then
        begin
          SetLength(FSteps, Paths_.Count);
          for i := 0 to Paths_.Count - 1 do
            with FSteps[i] do
              begin
                Position := Paths_[i]^;
                if i > 0 then
                    Angle := CalcAngle(Paths_[i - 1]^, Paths_[i]^)
                else
                    Angle := CalcAngle(Position, Paths_[i]^);
                Index := i;
              end;
          FPause := False;
          FFromPosition := Position;
          FStopRollAngle := 0;
          FToPosition := Paths_.Last^;
          FOnInterface.StartBulletMovement;
        end;
    end;
end;

procedure TBulletMovementEngine.Start;
begin
  if (FActive) and (FPause) then
    begin
      FPause := False;
      FOnInterface.ResumeBullet;
    end;
end;

procedure TBulletMovementEngine.stop;
begin
  if FActive then
    begin
      SetLength(FSteps, 0);
      FCurrentPathStepTo := 0;
      FFromPosition := NULLPoint;
      FBulletMovementDone := False;
      FRollDone := True;
      FPause := False;
      FActive := False;
      FOperationMode := bmmBulletMovementPath;
      FOnInterface.StopBullet;
    end;
end;

procedure TBulletMovementEngine.Pause;
begin
  if not FPause then
    begin
      FPause := True;
      if FActive then
          FOnInterface.PauseBullet;
    end;
end;

procedure TBulletMovementEngine.Progress(const deltaTime: Double);
var
  CurrentDeltaTime: Double;
  toStep: TBulletMovementStepData;
  FromV, ToV, v: TVec2;
  dt, RT: Double;
  d: TGeoFloat;
  Order_: TStepHistoryData;
begin
  FLastProgressDeltaTime := deltaTime;
  if FActive then
    begin
      CurrentDeltaTime := deltaTime;
      FActive := (length(FSteps) > 0) or (FOperationMode = bmmStopRollAngle);
      if (not FPause) and (FActive) then
        begin
          FOnInterface.BulletProgress(CurrentDeltaTime);

          case FOperationMode of
            bmmStopRollAngle:
              begin
                RollAngle := SmoothAngle(RollAngle, FStopRollAngle, deltaTime * FRollSpeed);
                FActive := not AngleEqual(RollAngle, FStopRollAngle);
              end;
            bmmBulletMovementPath:
              begin
                FromV := Position;

                while True do
                  begin
                    if FBulletMovementDone and FRollDone then
                      begin
                        FActive := False;
                        Break;
                      end;

                    if FBulletMovementDone and not FRollDone then
                      begin
                        RollAngle := SmoothAngle(RollAngle, LastStep.Angle, deltaTime * FRollSpeed);
                        FRollDone := not AngleEqual(RollAngle, LastStep.Angle);
                        Break;
                      end;

                    if FCurrentPathStepTo >= length(FSteps) then
                      begin
                        v := LastStep.Position;
                        Position := v;
                        if not AngleEqual(RollAngle, LastStep.Angle) then
                          begin
                            FOperationMode := bmmStopRollAngle;
                            FStopRollAngle := LastStep.Angle;
                          end
                        else
                            FActive := False;
                        Break;
                      end;

                    toStep := FSteps[FCurrentPathStepTo];
                    ToV := toStep.Position;
                    FBulletMovementDone := FCurrentPathStepTo >= length(FSteps);

                    if (FRollDone) and (not AngleEqual(RollAngle, toStep.Angle)) then
                        FOnInterface.StartBulletRoll;

                    if (not FRollDone) and (AngleEqual(RollAngle, toStep.Angle)) then
                        FOnInterface.DoneBulletRoll;

                    FRollDone := AngleEqual(RollAngle, toStep.Angle);

                    if FRollDone then
                      begin
                        dt := MovementDistanceDeltaTime(FromV, ToV, FMoveSpeed);
                        if dt > CurrentDeltaTime then
                          begin
                            // direct compute
                            v := MovementDistance(FromV, ToV, CurrentDeltaTime * FMoveSpeed);
                            Position := v;
                            Break;
                          end
                        else
                          begin
                            CurrentDeltaTime := CurrentDeltaTime - dt;
                            FromV := ToV;
                            inc(FCurrentPathStepTo);

                            // trigger event
                            if (FCurrentPathStepTo < length(FSteps)) then
                                FOnInterface.BulletStep(toStep, FSteps[FCurrentPathStepTo]);
                          end;
                      end
                    else
                      begin
                        // uses roll attenuation
                        RT := AngleRollDistanceDeltaTime(RollAngle, toStep.Angle, FRollSpeed);
                        d := Distance(FromV, ToV);

                        if RT >= CurrentDeltaTime then
                          begin
                            if d > CurrentDeltaTime * FMoveSpeed then
                              begin
                                // position vector dont cross endge
                                v := MovementDistance(FromV, ToV, CurrentDeltaTime * FMoveSpeed);
                                Position := v;
                                RollAngle := SmoothAngle(RollAngle, toStep.Angle, CurrentDeltaTime * FRollSpeed);
                                Break;
                              end
                            else
                              begin
                                // position vector cross endge
                                dt := MovementDistanceDeltaTime(FromV, ToV, FMoveSpeed);
                                v := ToV;
                                Position := v;
                                RollAngle := SmoothAngle(RollAngle, toStep.Angle, dt * FRollSpeed);
                                CurrentDeltaTime := CurrentDeltaTime - dt;
                                FromV := ToV;
                                inc(FCurrentPathStepTo);

                                // trigger event
                                if (FCurrentPathStepTo < length(FSteps)) then
                                    FOnInterface.BulletStep(toStep, FSteps[FCurrentPathStepTo]);
                              end;
                          end
                        else
                          begin
                            // preprocess roll speed attenuation
                            if RT * FMoveSpeed > d then
                              begin
                                // position vector cross endge
                                dt := MovementDistanceDeltaTime(FromV, ToV, FMoveSpeed);
                                v := ToV;
                                Position := v;
                                RollAngle := SmoothAngle(RollAngle, toStep.Angle, dt * FRollSpeed);
                                CurrentDeltaTime := CurrentDeltaTime - dt;
                                FromV := ToV;
                                inc(FCurrentPathStepTo);

                                // trigger event
                                if (FCurrentPathStepTo < length(FSteps)) then
                                    FOnInterface.BulletStep(toStep, FSteps[FCurrentPathStepTo]);
                              end
                            else
                              begin
                                // position vector dont cross endge
                                v := MovementDistance(FromV, ToV, RT * FMoveSpeed);
                                Position := v;
                                RollAngle := toStep.Angle;
                                CurrentDeltaTime := CurrentDeltaTime - RT;
                              end;
                          end;
                      end;
                  end;
              end;
          end;

          if (not FActive) then
            begin
              FCurrentPathStepTo := 0;
              FFromPosition := NULLPoint;
              FBulletMovementDone := False;
              FRollDone := False;
              FOperationMode := bmmBulletMovementPath;
              FOnInterface.DoneBulletMovement;
              FStepHistory.Clear;
            end
          else if FMaxStepHistoryNum > 0 then
            begin
              Order_.Position := Position;
              Order_.Angle := RollAngle;
              FStepHistory.Push(Order_);
              while FStepHistory.Num > FMaxStepHistoryNum do
                  FStepHistory.Next;
            end;
        end;
    end;
end;

end.
 
