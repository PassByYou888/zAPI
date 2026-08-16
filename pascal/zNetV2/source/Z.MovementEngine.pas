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
  * Z.MovementEngine – 2D Path Following and Smooth Rotation Engine.
  *
  * This unit provides a movement engine that drives an object along a
  * predefined path (a sequence of waypoints) while smoothly rotating its
  * orientation toward the next waypoint. It supports two modes:
  * path‑following and simple angle‑stopping (rotate in place without moving).
  *
  * The engine communicates with the controlled object via the
  * IMovementEngineInterface callback interface. This design decouples the
  * movement logic from the specific object type (sprite, vehicle, camera,
  * etc.). The host object implements the interface to provide position/angle
  * access and to receive event notifications.
  *
  * ===========================================================================
  * Core features
  * ===========================================================================
  *   – Path following – moves through a list of 2D waypoints in order.
  *   – Smooth rotation – gradually turns toward the heading of the next segment.
  *   – Configurable speeds – separate movement speed and rotation speed.
  *   – Roll‑while‑moving – can begin rotating before reaching a waypoint,
  *     controlled by the RollMoveThreshold property for smoother turns.
  *   – Loop mode – automatically restarts the path when the end is reached.
  *   – Pause/Resume – pause and resume movement at any time.
  *   – Two operation modes:
  *       * momMovementPath – follow a sequence of waypoints.
  *       * momStopRollAngle – rotate to a target angle without moving.
  *
  * ===========================================================================
  * Typical usage
  * ===========================================================================
  *   // 1. Define a class that implements IMovementEngineInterface.
  *   // 2. Create a TMovementEngine instance and assign the interface.
  *   // 3. Call Start(Paths_) to begin following a path.
  *   // 4. In the main loop, call Progress(deltaTime) each frame.
  *
  *   @Example:
  *     var
  *       Engine: TMovementEngine;
  *       Path: TV2L;
  *     begin
  *       Engine := TMovementEngine.Create;
  *       Engine.OnInterface := MySprite;   // MySprite implements the interface
  *       Engine.MoveSpeed := 150;          // 150 units per second
  *       Engine.RollSpeed := 90;           // 90 degrees per second
  *       Engine.RollMoveThreshold := 0.3;  // Move at 30% speed while turning
  *       Engine.Looped := True;            // Loop the path indefinitely
  *
  *       Path := TV2L.Create;
  *       Path.Add(0, 0);    // Waypoint 1
  *       Path.Add(100, 0);  // Waypoint 2
  *       Path.Add(100, 100);// Waypoint 3
  *       Path.Add(0, 100);  // Waypoint 4
  *       Engine.Start(Path);
  *
  *       // In the main loop:
  *       while Running do
  *       begin
  *         Engine.Progress(DeltaTime);
  *         // The sprite's position and angle are updated automatically
  *         // via the interface callbacks.
  *       end;
  *     end;
  *
  * ===========================================================================
  * Event sequence during movement
  * ===========================================================================
  *   When Start() is called:
  *     1. DoStartMovement() is fired.
  *     2. The engine calculates the angle toward the first waypoint.
  *     3. Progress() updates position and rotation each frame.
  *     4. When a waypoint is reached, DoMovementStepChange() fires.
  *     5. If the engine finishes rotating toward the next step, DoRollMovementOver() fires.
  *     6. When the last waypoint is reached, DoMovementDone() fires.
  *     7. If Looped is True, DoLoop() fires and the path restarts.
  *
  * ===========================================================================
  * Dependencies
  * ===========================================================================
  *   – Z.Core            – for TCore_Object_Intermediate and base types.
  *   – Z.Geometry2D      – for TVec2, TGeoFloat, and geometric helpers.
  *   – Z.Geometry3D      – for SmoothAngle, AngleDistance, AngleEqual.
}
unit Z.MovementEngine;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses Z.Core, Z.Geometry2D;

type
  { ----------------------------------------------------------------------------
    TMovementStepData – a single waypoint in a movement path.

    This record stores the target position, the desired heading angle when
    moving toward this step, and its sequential index in the path. The angle
    is typically computed as the direction from the previous step to this step,
    or from the current position to the first step.
  }
  TMovementStepData = record
    Position: TVec2; // Target 2D position of this waypoint.
    Angle: TGeoFloat; // Desired heading angle in degrees at this waypoint.
    Index: Integer; // Sequential index in the path (0‑based).
  end;

  { ----------------------------------------------------------------------------
    IMovementEngineInterface – callback interface for movement engine events.

    The host object (e.g., a sprite, vehicle, or character) must implement
    this interface to provide position/angle access and to receive event
    notifications. This design allows the engine to be reused with any
    object type without inheritance.

    All methods are called by the TMovementEngine during its Progress()
    update loop.
  }
  IMovementEngineInterface = interface
    { * Returns the current 2D position of the controlled object. }
    function GetPosition: TVec2;

    { * Sets the current 2D position of the controlled object. }
    procedure SetPosition(const Value: TVec2);

    { * Returns the current heading (roll) angle of the controlled object
      * in degrees. }
    function GetRollAngle: TGeoFloat;

    { * Sets the current heading (roll) angle in degrees. }
    procedure SetRollAngle(const Value: TGeoFloat);

    { * Called when the engine begins a new movement session. }
    procedure DoStartMovement;

    { * Called when the movement session completes (all steps reached). }
    procedure DoMovementDone;

    { * Called when the engine starts rotating toward the next step's angle. }
    procedure DoRollMovementStart;

    { * Called when the engine finishes rotating to the target angle. }
    procedure DoRollMovementOver;

    { * Called when the path loops back to the start (if Looped is True). }
    procedure DoLoop;

    { * Called when the engine is stopped via the Stop method. }
    procedure DoStop;

    { * Called when the engine is paused. }
    procedure DoPause;

    { * Called when the engine resumes from a paused state. }
    procedure DoResume;

    { * Called when the engine moves from one step to the next in the path.
      * @param OldStep the previous waypoint data.
      * @param NewStep the new waypoint data.
    }
    procedure DoMovementStepChange(OldStep, NewStep: TMovementStepData);
  end;

  { ----------------------------------------------------------------------------
    TMovementOperationMode – the engine's operating mode.

    - momMovementPath : follow a sequence of waypoints, moving and rotating.
    - momStopRollAngle : stay in place and rotate toward a target angle.
  }
  TMovementOperationMode = (momMovementPath, momStopRollAngle);

  { ----------------------------------------------------------------------------
    TMovementEngine – main movement engine class.

    Drives an object along a path defined by waypoints, or rotates it to a
    target angle. It uses the callback interface to read/write position and
    angle, and to notify the host of events. The engine is time‑driven via
    the Progress() method, which should be called each frame with the elapsed
    delta time.

    The engine handles the following logic per frame:
    – Moves the object along the current segment at MoveSpeed units/second.
    – Rotates the object toward the next waypoint's angle at RollSpeed degrees/second.
    – If the object is rotating, movement speed is attenuated by RollMoveThreshold.
    – Detects waypoint arrivals and fires step-change events.
    – Handles loop mode and completion detection.
  }
  TMovementEngine = class(TCore_Object_Intermediate)
  private
    FOnInterface: IMovementEngineInterface; // Callback interface to the host object.
    FSteps: array of TMovementStepData; // Array of waypoints defining the path.
    FActive: Boolean; // True if the engine is currently running.
    FPause: Boolean; // True if movement is paused.
    FMoveSpeed: TGeoFloat; // Movement speed (units per second).
    FRollSpeed: TGeoFloat; // Rotation speed (degrees per second).
    FRollMoveThreshold: TGeoFloat; // Fraction of speed used during rotation.
    FOperationMode: TMovementOperationMode; // Current operating mode.
    FLooped: Boolean; // If True, restart path when complete.
    FStopRollAngle: TGeoFloat; // Target angle for stop‑and‑rotate mode.
    FLastProgressNewTime: Double; // Timestamp of last progress call (unused).
    FLastProgressDeltaTime: Double; // Last delta time passed to Progress.
    FCurrentPathStepTo: Integer; // Index of the next waypoint to reach.
    FFromPosition: TVec2; // Position at start of current segment.
    FToPosition: TVec2; // Destination of current segment.
    FMovementDone, FRollDone: Boolean; // Flags for segment completion.

  protected
    { * Returns the current position via the interface. }
    function GetPosition: TVec2;

    { * Sets the current position via the interface. }
    procedure SetPosition(const Value: TVec2);

    { * Returns the current roll angle via the interface. }
    function GetRollAngle: TGeoFloat;

    { * Sets the current roll angle via the interface. }
    procedure SetRollAngle(const Value: TGeoFloat);

    { * Returns the first waypoint in the path. Assumes FSteps is not empty. }
    function FirstStep: TMovementStepData;

    { * Returns the last waypoint in the path. Assumes FSteps is not empty. }
    function LastStep: TMovementStepData;

  public
    constructor Create;
    destructor Destroy; override;

    { * Starts movement toward a single target position.
      * The engine will rotate in place to face the target without moving
      * (momStopRollAngle mode). This is useful for orienting an object
      * toward a point.
      * @param To_ The target position to face.
      * @Example:
      *   Engine.Start(Vec2(100, 50)); // Rotate to face (100, 50)
    }
    procedure Start(To_: TVec2); overload;

    { * Starts movement along a path defined by a list of waypoints.
      * The engine moves through the points in order, rotating to face
      * each segment's direction. The path is copied internally; the caller
      * can free the TV2L after calling Start.
      * @param Paths_ A TV2L list of waypoints (must not be nil or empty).
      * @Example:
      *   var Path: TV2L;
      *   begin
      *     Path := TV2L.Create;
      *     Path.Add(0, 0);
      *     Path.Add(100, 0);
      *     Path.Add(100, 100);
      *     Engine.Start(Path);   // Moves through these three points
      *   end;
    }
    procedure Start(Paths_: TV2L); overload;

    { * Resumes a paused movement session.
      * If the engine is active and paused, it will resume. This has no
      * effect if the engine is not paused.
      * @Example:
      *   Engine.Pause;   // Pause movement
      *   // ... later ...
      *   Engine.Start;   // Resume from where it left off
    }
    procedure Start; overload;

    { * Stops the current movement session immediately.
      * The engine resets all internal state (active flag, step counter,
      * and completion flags) and fires DoStop. After stopping, the engine
      * must be restarted with a new Start() call.
      * @Example:
      *   Engine.Stop;   // Immediately stop all movement
    }
    procedure stop;

    { * Pauses the current movement session.
      * The engine retains its state (position, current step, etc.) but
      * stops updating. Use Start() without parameters to resume.
      * @Example:
      *   Engine.Pause;   // Freeze the object in place
    }
    procedure Pause;

    { * Advances the engine by the given delta time.
      * This method should be called every frame with the elapsed time since
      * the last call. It updates position and angle, and fires events as
      * waypoints are reached or when the session completes.
      * @param deltaTime Time elapsed since the last update (in seconds).
      * @Example:
      *   // In the game loop:
      *   Engine.Progress(DeltaTime);
    }
    procedure Progress(const deltaTime: Double);

    { * The callback interface used by the engine to communicate with the host.
      * This must be assigned before calling Start().
    }
    property OnInterface: IMovementEngineInterface read FOnInterface write FOnInterface;

    { * Current 2D position (read/write via the interface). }
    property Position: TVec2 read GetPosition write SetPosition;

    { * Current heading angle in degrees (read/write via the interface). }
    property RollAngle: TGeoFloat read GetRollAngle write SetRollAngle;

    { * True if the engine is paused. }
    property IsPause: Boolean read FPause;

    { * True if the engine is currently active (running). }
    property Active: Boolean read FActive;

    { * Movement speed in units per second.
      * Default is 100 units/second.
    }
    property MoveSpeed: TGeoFloat read FMoveSpeed write FMoveSpeed;

    { * Rotation speed in degrees per second.
      * Default is 180 degrees/second.
    }
    property RollSpeed: TGeoFloat read FRollSpeed write FRollSpeed;

    { * Threshold multiplier for movement speed during rotation.
      * When the engine is rotating toward the next waypoint's angle, it
      * can still move forward at a reduced speed. This property controls
      * that reduction: actual speed = MoveSpeed * RollMoveThreshold.
      * A value of 0.5 means the object moves at half speed while turning.
      * Default is 0.5.
    }
    property RollMoveThreshold: TGeoFloat read FRollMoveThreshold write FRollMoveThreshold;

    { * The current operation mode (path following or angle stopping).
      * This is set automatically by Start() overloads.
    }
    property OperationMode: TMovementOperationMode read FOperationMode write FOperationMode;

    { * If True, the path will loop when the end is reached.
      * When looping, the engine restarts from the first waypoint and fires
      * DoLoop. Default is False.
    }
    property Looped: Boolean read FLooped write FLooped;

    { * Position at the start of the current path segment. }
    property FromPosition: TVec2 read FFromPosition;

    { * Destination position of the current path segment. }
    property ToPosition: TVec2 read FToPosition;
  end;

implementation

uses Z.Geometry3D;

function TMovementEngine.GetPosition: TVec2;
begin
  Result := FOnInterface.GetPosition;
end;

procedure TMovementEngine.SetPosition(const Value: TVec2);
begin
  FOnInterface.SetPosition(Value);
end;

function TMovementEngine.GetRollAngle: TGeoFloat;
begin
  Result := FOnInterface.GetRollAngle;
end;

procedure TMovementEngine.SetRollAngle(const Value: TGeoFloat);
begin
  FOnInterface.SetRollAngle(Value);
end;

function TMovementEngine.FirstStep: TMovementStepData;
begin
  Result := FSteps[0];
end;

function TMovementEngine.LastStep: TMovementStepData;
begin
  Result := FSteps[length(FSteps) - 1];
end;

constructor TMovementEngine.Create;
begin
  inherited Create;
  SetLength(FSteps, 0);
  FOnInterface := nil;

  FActive := False;
  FPause := False;
  FMoveSpeed := 100;
  FRollSpeed := 180;
  FRollMoveThreshold := 0.5;
  FOperationMode := momMovementPath;

  FLooped := False;
  FStopRollAngle := 0;

  FLastProgressDeltaTime := 0;

  FCurrentPathStepTo := -1;

  FFromPosition := NULLPoint;
  FToPosition := NULLPoint;

  FMovementDone := False;
  FRollDone := False;
end;

destructor TMovementEngine.Destroy;
begin
  SetLength(FSteps, 0);
  FOnInterface := nil;
  inherited Destroy;
end;

procedure TMovementEngine.Start(To_: TVec2);
begin
  if not FActive then
    begin
      SetLength(FSteps, 0);
      FStopRollAngle := CalcAngle(Position, To_);
      FOperationMode := momStopRollAngle;
      FActive := True;
      FPause := False;
      FToPosition := To_;
      FOnInterface.DoStartMovement;
    end;
end;

procedure TMovementEngine.Start(Paths_: TV2L);
var
  i: Integer;
begin
  Paths_.RemoveSame;

  if not FActive then
    begin
      FCurrentPathStepTo := 0;
      FFromPosition := NULLPoint;
      FMovementDone := False;
      FRollDone := False;
      FOperationMode := momMovementPath;

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
                index := i;
              end;

          FPause := False;
          FFromPosition := Position;

          FStopRollAngle := 0;

          FToPosition := Paths_.Last^;
          FOnInterface.DoStartMovement;
        end;
    end;
end;

procedure TMovementEngine.Start;
begin
  if (FActive) and (FPause) then
    begin
      FPause := False;
      FOnInterface.DoResume;
    end;
end;

procedure TMovementEngine.stop;
begin
  if FActive then
    begin
      SetLength(FSteps, 0);
      FCurrentPathStepTo := 0;
      FFromPosition := NULLPoint;
      FMovementDone := False;
      FRollDone := True;
      FPause := False;
      FActive := False;
      FOperationMode := momMovementPath;
      FOnInterface.DoStop;
    end;
end;

procedure TMovementEngine.Pause;
begin
  if not FPause then
    begin
      FPause := True;
      if FActive then
          FOnInterface.DoPause;
    end;
end;

procedure TMovementEngine.Progress(const deltaTime: Double);
var
  CurrentDeltaTime: Double;
  toStep: TMovementStepData;
  FromV, ToV, v: TVec2;
  dt, RT: Double;
  d: TGeoFloat;
begin
  FLastProgressDeltaTime := deltaTime;
  if FActive then
    begin
      CurrentDeltaTime := deltaTime;
      FActive := (length(FSteps) > 0) or (FOperationMode = momStopRollAngle);
      if (not FPause) and (FActive) then
        begin
          case FOperationMode of
            momStopRollAngle:
              begin
                RollAngle := SmoothAngle(RollAngle, FStopRollAngle, deltaTime * FRollSpeed);
                FActive := not AngleEqual(RollAngle, FStopRollAngle);
              end;
            momMovementPath:
              begin
                FromV := Position;

                while True do
                  begin
                    if FMovementDone and FRollDone then
                      begin
                        FActive := False;
                        Break;
                      end;

                    if FMovementDone and not FRollDone then
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
                            FOperationMode := momStopRollAngle;
                            FStopRollAngle := LastStep.Angle;
                          end
                        else
                            FActive := False;
                        Break;
                      end;

                    toStep := FSteps[FCurrentPathStepTo];
                    ToV := toStep.Position;
                    FMovementDone := FCurrentPathStepTo >= length(FSteps);

                    if (FRollDone) and (not AngleEqual(RollAngle, toStep.Angle)) then
                        FOnInterface.DoRollMovementStart;

                    if (not FRollDone) and (AngleEqual(RollAngle, toStep.Angle)) then
                        FOnInterface.DoRollMovementOver;

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
                                FOnInterface.DoMovementStepChange(toStep, FSteps[FCurrentPathStepTo]);
                          end;
                      end
                    else
                      begin
                        // uses roll attenuation

                        RT := AngleRollDistanceDeltaTime(RollAngle, toStep.Angle, FRollSpeed);
                        d := Distance(FromV, ToV);

                        if RT >= CurrentDeltaTime then
                          begin
                            if d > CurrentDeltaTime * FMoveSpeed * FRollMoveThreshold then
                              begin
                                // position vector dont cross endge
                                v := MovementDistance(FromV, ToV, CurrentDeltaTime * FMoveSpeed * FRollMoveThreshold);
                                Position := v;
                                RollAngle := SmoothAngle(RollAngle, toStep.Angle, CurrentDeltaTime * FRollSpeed);
                                Break;
                              end
                            else
                              begin
                                // position vector cross endge
                                dt := MovementDistanceDeltaTime(FromV, ToV, FMoveSpeed * FRollMoveThreshold);
                                v := ToV;
                                Position := v;
                                RollAngle := SmoothAngle(RollAngle, toStep.Angle, dt * FRollSpeed);
                                CurrentDeltaTime := CurrentDeltaTime - dt;
                                FromV := ToV;
                                inc(FCurrentPathStepTo);

                                // trigger event
                                if (FCurrentPathStepTo < length(FSteps)) then
                                    FOnInterface.DoMovementStepChange(toStep, FSteps[FCurrentPathStepTo]);
                              end;
                          end
                        else
                          begin
                            // preprocess roll movement speed attenuation
                            if RT * FMoveSpeed * FRollMoveThreshold > d then
                              begin
                                // position vector cross endge
                                dt := MovementDistanceDeltaTime(FromV, ToV, FMoveSpeed * FRollMoveThreshold);
                                v := ToV;
                                Position := v;
                                RollAngle := SmoothAngle(RollAngle, toStep.Angle, dt * FRollSpeed);
                                CurrentDeltaTime := CurrentDeltaTime - dt;
                                FromV := ToV;
                                inc(FCurrentPathStepTo);

                                // trigger event
                                if (FCurrentPathStepTo < length(FSteps)) then
                                    FOnInterface.DoMovementStepChange(toStep, FSteps[FCurrentPathStepTo]);
                              end
                            else
                              begin
                                // position vector dont cross endge
                                v := MovementDistance(FromV, ToV, RT * FMoveSpeed * FRollMoveThreshold);
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
              if (FLooped) and (length(FSteps) > 0) then
                begin
                  FCurrentPathStepTo := 0;
                  FActive := True;
                  FMovementDone := False;
                  FRollDone := False;
                  FOperationMode := momMovementPath;
                  FSteps[0].Angle := CalcAngle(Position, FSteps[0].Position);
                  FOnInterface.DoLoop;
                end
              else
                begin
                  FCurrentPathStepTo := 0;
                  FFromPosition := NULLPoint;
                  FMovementDone := False;
                  FRollDone := False;
                  FOperationMode := momMovementPath;
                  FOnInterface.DoMovementDone;
                end;
            end;
        end;
    end;
end;

end.
 
