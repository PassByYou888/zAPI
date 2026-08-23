object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'vclclient'
  ClientHeight = 442
  ClientWidth = 628
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OldCreateOrder = True
  OnDestroy = Button3Click
  DesignSize = (
    628
    442)
  PixelsPerInch = 96
  TextHeight = 15
  object Text5: TLabel
    Left = 8
    Top = 73
    Width = 9
    Height = 15
    Anchors = [akLeft, akTop, akRight]
    Caption = '   '
  end
  object Button1: TButton
    Left = 8
    Top = 8
    Width = 233
    Height = 25
    Caption = #36830#25509#21040#26381#21153#65288#32431#28040#36153#31471#65292#19981#26292#38706' API'#65289
    TabOrder = 0
    OnClick = Button1Click
  end
  object Button2: TButton
    Left = 8
    Top = 39
    Width = 113
    Height = 25
    Caption = #35843#29992#20989#25968'add'
    Enabled = False
    TabOrder = 1
    OnClick = Button2Click
  end
  object Memo1: TMemo
    Left = 0
    Top = 96
    Width = 628
    Height = 346
    Align = alBottom
    Anchors = [akLeft, akTop, akRight, akBottom]
    ScrollBars = ssBoth
    TabOrder = 2
    WordWrap = False
    ExplicitWidth = 622
    ExplicitHeight = 337
  end
  object Button3: TButton
    Left = 523
    Top = 8
    Width = 91
    Height = 25
    Anchors = [akTop, akRight]
    Caption = #20851#38381#23458#25143#31471
    Enabled = False
    TabOrder = 3
    OnClick = Button3Click
    ExplicitLeft = 517
  end
  object Button4: TButton
    Left = 426
    Top = 42
    Width = 91
    Height = 25
    Anchors = [akTop, akRight]
    Caption = #24182#21457#27979#35797
    Enabled = False
    TabOrder = 4
    OnClick = Button4Click
    ExplicitLeft = 420
  end
  object Button5: TButton
    Left = 136
    Top = 39
    Width = 113
    Height = 25
    Caption = #35843#29992#20989#25968'jsonceshi'
    Enabled = False
    TabOrder = 5
    OnClick = Button5Click
  end
  object Button6: TButton
    Left = 523
    Top = 42
    Width = 91
    Height = 25
    Anchors = [akTop, akRight]
    Caption = #28165#31354
    TabOrder = 6
    OnClick = Button6Click
    ExplicitLeft = 517
  end
end
