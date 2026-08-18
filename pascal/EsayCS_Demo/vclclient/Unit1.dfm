object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Form1'
  ClientHeight = 442
  ClientWidth = 628
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnDestroy = Button3Click
  DesignSize = (
    628
    442)
  TextHeight = 15
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
    Width = 137
    Height = 25
    Caption = #35775#38382#20855#20307#26381#21153
    Enabled = False
    TabOrder = 1
    OnClick = Button2Click
  end
  object Memo1: TMemo
    Left = 0
    Top = 70
    Width = 628
    Height = 372
    Align = alBottom
    Anchors = [akLeft, akTop, akRight, akBottom]
    TabOrder = 2
  end
  object Button3: TButton
    Left = 491
    Top = 8
    Width = 137
    Height = 25
    Anchors = [akTop, akRight]
    Caption = #20851#38381#23458#25143#31471
    Enabled = False
    TabOrder = 3
    OnClick = Button3Click
  end
end
