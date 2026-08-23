object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'vclEasyServer'
  ClientHeight = 191
  ClientWidth = 452
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OldCreateOrder = True
  OnDestroy = Button2Click
  DesignSize = (
    452
    191)
  PixelsPerInch = 96
  TextHeight = 15
  object Button1: TButton
    Left = 8
    Top = 8
    Width = 145
    Height = 25
    Caption = #21551#21160#26381#21153#21151#33021
    TabOrder = 0
    OnClick = Button1Click
  end
  object Memo1: TMemo
    Left = 0
    Top = 39
    Width = 452
    Height = 152
    Align = alBottom
    TabOrder = 1
    ExplicitTop = 30
    ExplicitWidth = 446
  end
  object Button2: TButton
    Left = 293
    Top = 8
    Width = 145
    Height = 25
    Anchors = [akTop, akRight]
    Caption = #20572#27490#26381#21153#21151#33021
    TabOrder = 2
    OnClick = Button2Click
    ExplicitLeft = 287
  end
end
