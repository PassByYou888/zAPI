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
{ ****************************************************************************** }
{ * Line 2D Templet - A Generic 2D Line Drawing Engine                         * }
{ ****************************************************************************** }
unit Z.Line2D.Templet;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses Z.Core;

type
  {
    TLine_2D_Templet<T_> is a generic template class for drawing lines,
    rectangles, and filled boxes onto a 2D array of arbitrary type T_.

    The class operates on a pointer to a rectangular memory buffer that
    represents a two-dimensional grid (width ¡Á height). It provides methods
    to draw vertical, horizontal, and arbitrary lines using the Bresenham
    line algorithm, as well as filled rectangles.

    The actual pixel processing is delegated to the virtual Process method,
    which by default assigns the specified value (FValue) to the target
    pixel. Subclasses can override Process to implement custom behavior
    such as blending, alpha compositing, or color manipulation.

    The FLineTail flag controls whether the last pixel of a line is drawn,
    which is useful for connecting line segments without overlapping
    endpoints.

    Usage:
      1. Derive a class from TLine_2D_Templet<T_> if custom pixel processing
         is required.
      2. Instantiate the class with a pointer to the pixel data buffer,
         dimensions, the value to draw, and the line-tail flag.
      3. Call the drawing methods (VertLine, HorzLine, Line, FillBox) to
         modify the buffer.

    @typeparam T_ The type of each element in the 2D array (e.g., Byte,
                   Integer, Single, a record, etc.).
  }
  TLine_2D_Templet<T_> = class(TCore_Object_Intermediate)
  public type
    {
      TTArry_ is a zero-based array type for convenient pointer arithmetic.
      It is used to treat the data buffer as a contiguous 1D array of T_.
      PTArry_ is a pointer to such an array.
    }
    TTArry_ = array [0 .. 0] of T_;
    PTArry_ = ^TTArry_;

    { PT_ is a pointer to a single element of type T_. }
    PT_ = ^T_;

  private
  var
    { FData points to the start of the 2D data buffer. The buffer is assumed
      to be organized in row-major order: element (x, y) is at offset
      (x + y * FWidth). }
    FData: PTArry_;

    { FWidth and FHeight define the dimensions of the 2D array. }
    FWidth, FHeight: NativeInt;

    { FValue is the value that will be written to pixels during drawing
      operations. }
    FValue: T_;

    { FLineTail determines whether the last pixel of a line is drawn.
      If True, the endpoint is included; otherwise, it is omitted.
      This is useful for chaining line segments without double-drawing
      shared endpoints. }
    FLineTail: Boolean;

  public
    {
      CreateDone is a virtual method called at the end of the constructor.
      It does nothing by default but can be overridden by descendant classes
      to perform additional initialization after the instance has been
      set up.
    }
    procedure CreateDone; virtual;

    {
      Constructs a TLine_2D_Templet instance.

      @param data_      Pointer to the start of the 2D data buffer.
                        The buffer must be at least (width_ * height_) elements.
      @param width_     The width (number of columns) of the 2D array.
      @param height_    The height (number of rows) of the 2D array.
      @param Value_     The default value to write during drawing operations.
      @param LineTail_  If True, line endpoints are drawn; if False, the last
                        pixel of a line is omitted.
    }
    constructor Create(const data_: Pointer; const width_, height_: NativeInt;
      const Value_: T_; const LineTail_: Boolean);

    destructor Destroy; override;

    {
      Draws a vertical line from (X, y1) to (X, y2).
      The line is clipped to the array bounds.

      @param X   The X coordinate (column index), must be within [0, FWidth-1].
      @param y1  Starting Y coordinate (row index).
      @param y2  Ending Y coordinate.
    }
    procedure VertLine(X, y1, y2: NativeInt);

    {
      Draws a horizontal line from (x1, Y) to (x2, Y).
      The line is clipped to the array bounds.

      @param x1  Starting X coordinate.
      @param Y   The Y coordinate (row index), must be within [0, FHeight-1].
      @param x2  Ending X coordinate.
    }
    procedure HorzLine(x1, Y, x2: NativeInt);

    {
      Draws an arbitrary line from (x1, y1) to (x2, y2) using the Bresenham
      line algorithm. The line is clipped to the array bounds.

      The behavior for the endpoint is controlled by FLineTail:
        - If FLineTail is True, the last pixel is drawn.
        - If False, the last pixel is omitted (useful for connecting lines).

      @param x1  Starting X coordinate.
      @param y1  Starting Y coordinate.
      @param x2  Ending X coordinate.
      @param y2  Ending Y coordinate.
    }
    procedure Line(x1, y1, x2, y2: NativeInt);

    {
      Fills a rectangular area from (x1, y1) to (x2, y2) by drawing
      horizontal lines for each row inside the rectangle. The rectangle
      is clipped to the array bounds.

      @param x1  Left edge X coordinate.
      @param y1  Top edge Y coordinate.
      @param x2  Right edge X coordinate.
      @param y2  Bottom edge Y coordinate.
    }
    procedure FillBox(x1, y1, x2, y2: NativeInt);

    {
      Process is a virtual method called for each pixel that is being
      drawn. The default implementation assigns the value v to the pixel
      pointed to by vp.

      Descendant classes can override this method to implement custom
      pixel handling, such as applying a color transformation, blending,
      or conditional writing.

      @param vp  Pointer to the pixel element in the data buffer.
      @param v   The value that is being written (usually FValue).
    }
    procedure Process(const vp: PT_; const v: T_); virtual;

    { Returns the current drawing value (FValue). }
    property Value: T_ read FValue;
  end;

implementation

{$IFDEF RangeCheck}{$R-}{$ENDIF}
{$IFDEF OverflowCheck}{$Q-}{$ENDIF}


procedure TLine_2D_Templet<T_>.CreateDone;
begin
end;

constructor TLine_2D_Templet<T_>.Create(const data_: Pointer; const width_, height_: NativeInt; const Value_: T_; const LineTail_: Boolean);
begin
  inherited Create;
  FData := PTArry_(data_);
  FWidth := width_;
  FHeight := height_;
  FValue := Value_;
  FLineTail := LineTail_;
  CreateDone();
end;

destructor TLine_2D_Templet<T_>.Destroy;
begin
  inherited Destroy;
end;

procedure TLine_2D_Templet<T_>.VertLine(X, y1, y2: NativeInt);
var
  i: NativeInt;
  p: PT_;
begin
  if (X < 0) or (X >= FWidth) then
      Exit;

  if y1 < 0 then
      y1 := 0;
  if y1 >= FHeight then
      y1 := FHeight - 1;

  if y2 < 0 then
      y2 := 0;
  if y2 >= FHeight then
      y2 := FHeight - 1;

  if y2 < y1 then
      TSwap<NativeInt>.Do_(y1, y2);

  p := @FData^[X + y1 * FWidth];
  for i := y1 to y2 do
    begin
      Process(p, FValue);
      inc(p, FWidth);
    end;
end;

procedure TLine_2D_Templet<T_>.HorzLine(x1, Y, x2: NativeInt);
var
  i: NativeInt;
  p: PT_;
begin
  if (Y < 0) or (Y >= FHeight) then
      Exit;

  if x1 < 0 then
      x1 := 0;
  if x1 >= FWidth then
      x1 := FWidth - 1;

  if x2 < 0 then
      x2 := 0;
  if x2 >= FWidth then
      x2 := FWidth - 1;

  if x1 > x2 then
      TSwap<NativeInt>.Do_(x1, x2);

  p := @FData^[x1 + Y * FWidth];

  for i := x1 to x2 do
    begin
      Process(p, FValue);
      inc(p);
    end;
end;

procedure TLine_2D_Templet<T_>.Line(x1, y1, x2, y2: NativeInt);
var
  dy, dx, SY, SX, i, Delta: NativeInt;
  pi, pl: NativeInt;
begin
  if (x1 = x2) and (y1 = y2) then
    begin
      Process(@FData^[x1 + y1 * FWidth], FValue);
      Exit;
    end;

  dx := x2 - x1;
  dy := y2 - y1;

  if dx > 0 then
      SX := 1
  else if dx < 0 then
    begin
      dx := -dx;
      SX := -1;
    end
  else // Dx = 0
    begin
      if dy > 0 then
          VertLine(x1, y1, y2 - 1)
      else if dy < 0 then
          VertLine(x1, y2 + 1, y1);
      if FLineTail then
          Process(@FData^[x2 + y2 * FWidth], FValue);
      Exit;
    end;

  if dy > 0 then
      SY := 1
  else if dy < 0 then
    begin
      dy := -dy;
      SY := -1;
    end
  else // Dy = 0
    begin
      if x2 > x1 then
          HorzLine(x1, y1, x2 - 1)
      else
          HorzLine(x2 + 1, y1, x1);
      if FLineTail then
          Process(@FData^[x2 + y2 * FWidth], FValue);
      Exit;
    end;

  pi := x1 + y1 * FWidth;
  SY := SY * FWidth;
  pl := FWidth * FHeight;

  if dx > dy then
    begin
      Delta := dx shr 1;
      for i := 0 to dx - 1 do
        begin
          if (pi >= 0) and (pi < pl) then
              Process(@FData^[pi], FValue);

          inc(pi, SX);
          inc(Delta, dy);
          if Delta >= dx then
            begin
              inc(pi, SY);
              dec(Delta, dx);
            end;
        end;
    end
  else // Dx < Dy
    begin
      Delta := dy shr 1;
      for i := 0 to dy - 1 do
        begin
          if (pi >= 0) and (pi < pl) then
              Process(@FData^[pi], FValue);

          inc(pi, SY);
          inc(Delta, dx);
          if Delta >= dy then
            begin
              inc(pi, SX);
              dec(Delta, dy);
            end;
        end;
    end;
  if (FLineTail) and (pi >= 0) and (pi < pl) then
      Process(@FData^[pi], FValue);
end;

procedure TLine_2D_Templet<T_>.FillBox(x1, y1, x2, y2: NativeInt);
var
  i: Integer;
begin
  if y1 > y2 then
      TSwap<NativeInt>.Do_(y1, y2);
  for i := y1 to y2 do
      HorzLine(x1, i, x2);
end;

procedure TLine_2D_Templet<T_>.Process(const vp: PT_; const v: T_);
begin
  vp^ := v;
end;
{$IFDEF RangeCheck}{$R+}{$ENDIF}
{$IFDEF OverflowCheck}{$Q+}{$ENDIF}


end.
 
