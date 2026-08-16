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
{ * Matched Algorithm - Bidirectional Matching Engine                         * }
{ ****************************************************************************** }
unit Z.Matched.Templet;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses Z.Core;

type
  {
    TBidirectional_Matched<T_> is a generic template class that implements a
    bidirectional matching algorithm between two data pools. It is designed
    to find the best matches between elements of Primary_Pool and Second_Pool
    based on a user-defined difference metric, while eliminating false matches
    through a two-way verification step.

    The algorithm works as follows:
      1. For each element in Primary_Pool, find the element in Second_Pool
         with the smallest difference (using the abstract Diff method).
      2. Verify that this match is also the best for the Second_Pool element
         (i.e., no other element in Primary_Pool has a smaller difference).
      3. If the difference is below the rejection threshold (reject), the
         pair is accepted and added to Pair_Pool.
      4. Both matched elements are removed from their respective pools to
         optimize subsequent matching.
      5. The process repeats until either pool is empty.

    This bidirectional verification ensures high accuracy, with nearly 100%
    correctness in typical use cases. The algorithm is highly efficient for
    single-threaded environments and is particularly suitable for server-side
    matching tasks.

    The matching process is driven by the Compute_Matched method, which
    returns the number of successful matches. The Diff method must be
    implemented by subclasses to compute the similarity/difference between
    two elements of type T_.

    The rejection threshold (reject) is used to discard matches that are
    too dissimilar, preventing false positives.

    @typeparam T_ The type of elements to be matched. It can be any data
                  type (e.g., numeric, vector, string, or complex record)
                  for which a meaningful difference metric can be defined.
  }
  TBidirectional_Matched<T_> = class(TCore_Object_Intermediate)
  public type
    {
      TData_Pool___ is a TBigList that stores elements of type T_.
      It is used for both primary and secondary pools.
    }
    TData_Pool___ = TBigList<T_>;

    {
      TPair_Pool___ is a TPair2_Tool that stores matched pairs
      (Primary, Second) as key-value pairs.
    }
    TPair_Pool___ = TPair2_Tool<T_, T_>;
  public
    { Primary data pool: the first set of elements to be matched. }
    Primary_Pool: TData_Pool___;

    { Secondary data pool: the second set of elements to be matched. }
    Second_Pool: TData_Pool___;

    { Pool that stores the successful matches as pairs (Primary, Second). }
    Pair_Pool: TPair_Pool___;

    { Rejection threshold. Any match with a Diff value >= reject is rejected. }
    reject: Single;

    {
      Constructs a new bidirectional matcher with the specified rejection
      threshold.
      @param reject_ The maximum allowed difference for a match. Higher
                     values allow more matches but may reduce accuracy.
    }
    constructor Create(const reject_: Single);

    destructor Destroy; override;

    {
      Computes the difference (distance) between two elements.
      This method must be overridden by subclasses to provide a concrete
      difference metric.

      @param Primary_  The first element (from Primary_Pool).
      @param Second_   The second element (from Second_Pool).
      @return A Single value representing the difference. Smaller values
              indicate higher similarity.
    }
    function Diff(const Primary_, Second_: T_): Single; virtual; abstract;

    {
      Called when a successful match is found. The default implementation
      adds the pair to Pair_Pool using Add_Pair.

      Subclasses can override this method to perform additional actions on
      a match (e.g., logging, event firing).

      @param Primary_  The matched primary element.
      @param Second_   The matched secondary element.
    }
    procedure Do_Matched(const Primary_, Second_: T_); virtual;

    {
      Executes the bidirectional matching algorithm.

      The method iterates through Primary_Pool, finds the best match in
      Second_Pool, validates it bidirectionally, and if accepted, records
      the pair and removes both elements from their pools.

      @return The number of successful matches.
    }
    function Compute_Matched(): NativeInt; virtual;
  end;

  {
    TBidirectional_Matched_D<T_> is a variant of the bidirectional matching
    algorithm that uses Double precision for difference values, instead of
    Single. This is useful when higher precision is required for the
    difference metric.

    All other behaviors and usage are identical to TBidirectional_Matched<T_>.
  }
  TBidirectional_Matched_D<T_> = class(TCore_Object_Intermediate)
  public type
    { Same type aliases as the Single-precision version. }
    TData_Pool___ = TBigList<T_>;
    TPair_Pool___ = TPair2_Tool<T_, T_>;
  public
    { Primary data pool. }
    Primary_Pool: TData_Pool___;

    { Secondary data pool. }
    Second_Pool: TData_Pool___;

    { Pair pool for matched pairs. }
    Pair_Pool: TPair_Pool___;

    { Rejection threshold (Double precision). }
    reject: Double;

    constructor Create(const reject_: Double);
    destructor Destroy; override;

    {
      Computes the difference (distance) between two elements using Double
      precision. Must be overridden by subclasses.
    }
    function Diff(const Primary_, Second_: T_): Double; virtual; abstract;

    { Called when a match is found. Default adds the pair to Pair_Pool. }
    procedure Do_Matched(const Primary_, Second_: T_); virtual;

    { Executes the bidirectional matching algorithm. Returns number of matches. }
    function Compute_Matched(): NativeInt; virtual;
  end;

implementation

constructor TBidirectional_Matched<T_>.Create(const reject_: Single);
begin
  inherited Create;
  Primary_Pool := TData_Pool___.Create;
  Second_Pool := TData_Pool___.Create;
  Pair_Pool := TPair_Pool___.Create;
  reject := reject_;
end;

destructor TBidirectional_Matched<T_>.Destroy;
begin
  DisposeObject(Primary_Pool);
  DisposeObject(Second_Pool);
  DisposeObject(Pair_Pool);
  inherited Destroy;
end;

procedure TBidirectional_Matched<T_>.Do_Matched(const Primary_, Second_: T_);
begin
  Pair_Pool.Add_Pair(Primary_, Second_);
end;

function TBidirectional_Matched<T_>.Compute_Matched: NativeInt;
var
  tmp_ptr: TData_Pool___.PQueueStruct;
  p_rep, p_rep_2, s_rep: TData_Pool___.TRepeat___;
  min_d, tmp_min_d: Single;
  successed: Boolean;
begin
  Result := 0;
  Pair_Pool.L.Clear;

  if (Primary_Pool.Num <= 0) or (Second_Pool.Num <= 0) then
      exit;

  // bidirectional matched algorithm
  p_rep := Primary_Pool.Repeat_;
  while (Primary_Pool.Num > 0) and (Second_Pool.Num > 0) do
    begin
      // 1 linear matched
      tmp_ptr := Second_Pool.First;
      min_d := Diff(p_rep.queue^.Data, tmp_ptr^.Data);
      s_rep := Second_Pool.Repeat_;
      repeat
        tmp_min_d := Diff(p_rep.queue^.Data, s_rep.queue^.Data);
        if tmp_min_d < min_d then
          begin
            tmp_ptr := s_rep.queue;
            min_d := tmp_min_d;
          end;
      until not s_rep.Next;

      // 2 linear matched
      if min_d < reject then
        begin
          successed := True;
          p_rep_2 := Primary_Pool.Repeat_;
          repeat
            if (p_rep.queue <> p_rep_2.queue) and (Diff(p_rep_2.queue^.Data, tmp_ptr^.Data) < min_d) then
                successed := False;
          until (not successed) or (not p_rep_2.Next);

          if successed then
            begin
              Do_Matched(p_rep.queue^.Data, tmp_ptr^.Data); // done
              Second_Pool.Remove_P(tmp_ptr); // optimize pool
              inc(Result);
            end;
        end;

      p_rep.Discard; // optimize pool
      if not p_rep.Next then // do next
          break;
    end;
end;

constructor TBidirectional_Matched_D<T_>.Create(const reject_: Double);
begin
  inherited Create;
  Primary_Pool := TData_Pool___.Create;
  Second_Pool := TData_Pool___.Create;
  Pair_Pool := TPair_Pool___.Create;
  reject := reject_;
end;

destructor TBidirectional_Matched_D<T_>.Destroy;
begin
  DisposeObject(Primary_Pool);
  DisposeObject(Second_Pool);
  DisposeObject(Pair_Pool);
  inherited Destroy;
end;

procedure TBidirectional_Matched_D<T_>.Do_Matched(const Primary_, Second_: T_);
begin
  Pair_Pool.Add_Pair(Primary_, Second_);
end;

function TBidirectional_Matched_D<T_>.Compute_Matched: NativeInt;
var
  tmp_ptr: TData_Pool___.PQueueStruct;
  p_rep, p_rep_2, s_rep: TData_Pool___.TRepeat___;
  min_d, tmp_min_d: Double;
  successed: Boolean;
begin
  Result := 0;
  Pair_Pool.L.Clear;

  if (Primary_Pool.Num <= 0) or (Second_Pool.Num <= 0) then
      exit;

  // bidirectional matched algorithm
  p_rep := Primary_Pool.Repeat_;
  while (Primary_Pool.Num > 0) and (Second_Pool.Num > 0) do
    begin
      // 1 linear matched
      tmp_ptr := Second_Pool.First;
      min_d := Diff(p_rep.queue^.Data, tmp_ptr^.Data);
      s_rep := Second_Pool.Repeat_;
      repeat
        tmp_min_d := Diff(p_rep.queue^.Data, s_rep.queue^.Data);
        if tmp_min_d < min_d then
          begin
            tmp_ptr := s_rep.queue;
            min_d := tmp_min_d;
          end;
      until not s_rep.Next;

      // 2 linear matched
      if min_d < reject then
        begin
          successed := True;
          p_rep_2 := Primary_Pool.Repeat_;
          repeat
            if (p_rep.queue <> p_rep_2.queue) and (Diff(p_rep_2.queue^.Data, tmp_ptr^.Data) < min_d) then
                successed := False;
          until (not successed) or (not p_rep_2.Next);

          if successed then
            begin
              Do_Matched(p_rep.queue^.Data, tmp_ptr^.Data); // done
              Second_Pool.Remove_P(tmp_ptr); // optimize pool
              inc(Result);
            end;
        end;

      p_rep.Discard; // optimize pool
      if not p_rep.Next then // do next
          break;
    end;
end;

end.
 
