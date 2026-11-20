/**
 * 雲隠れ（Kumogakure）W0-1: Google フォーム 2 種の一括生成スクリプト（Google Apps Script）
 *
 * 使い方:
 *   1. https://script.google.com/ を開き「新しいプロジェクト」を作成
 *   2. 本ファイルの内容をそのまま貼り付けて保存（Ctrl/Cmd + S）
 *   3. 上部ツールバーで関数 `createKumogakureForms` を選び「実行」をクリック
 *   4. 初回のみ Google フォーム作成権限の承認ダイアログを許可
 *   5. 実行ログに出力される URL 2 件と `REPORT_FORM_URL_TEMPLATE` を控える
 *   6. 出力された両方の「編集 URL」を開き、「回答」タブ →「⋮」→
 *      「新しい回答についてのメール通知を受け取る」を ON にしてテスト送信を実施
 *
 * 注意:
 *   本スクリプトは `FormApp` スコープのみを使用し、Gmail 等の追加権限は要求しません。
 */
function createKumogakureForms() {
  // ---------------------------------------------------------------------------
  // フォーム ①: お問い合わせ・不具合報告フォーム
  // ---------------------------------------------------------------------------
  var inquiryForm = FormApp.create('雲隠れ（Kumogakure）お問い合わせ・不具合報告');
  inquiryForm.setDescription(
    'デジタルデトックスアプリ「雲隠れ（Kumogakure）」へのお問い合わせ・不具合報告・ご要望・データ削除依頼の窓口です。\n' +
    '原則として個人情報はご入力にならないでください（返信をご希望の場合のみメールアドレスをご記入ください）。'
  );
  inquiryForm.setCollectEmail(false);
  inquiryForm.setAllowResponseEdits(false);
  inquiryForm.setLimitOneResponsePerUser(false);
  inquiryForm.setPublishingSummary(false);
  inquiryForm.setConfirmationMessage(
    'お問い合わせを受け付けました。ご連絡ありがとうございます。'
  );

  inquiryForm.addMultipleChoiceItem()
    .setTitle('お問い合わせ種別')
    .setChoiceValues([
      '不具合の報告',
      '機能のご要望',
      '隠者プラン（課金・復元）について',
      '不在証明ページの削除依頼',
      'その他のお問い合わせ'
    ])
    .setRequired(true);

  inquiryForm.addParagraphTextItem()
    .setTitle('お問い合わせ内容')
    .setHelpText(
      '発生した状況やご要望の内容をお知らせください。不在証明ページの削除依頼の場合は対象 URL またはセッション ID（/s/xxxxxxxxxx の末尾 10 文字）もご記入ください。'
    )
    .setRequired(true);

  inquiryForm.addTextItem()
    .setTitle('ご利用端末・iOS バージョン')
    .setHelpText('例: iPhone 15 / iOS 18.1')
    .setRequired(false);

  inquiryForm.addTextItem()
    .setTitle('匿名サポート ID（アプリ設定画面で確認可能）')
    .setHelpText(
      'アプリ内の「設定」＞「匿名サポート ID」をコピーして貼り付けてください（調査が必要な場合のみ）。'
    )
    .setRequired(false);

  var emailValidation = FormApp.createTextValidation()
    .requireTextIsEmail()
    .setHelpText('有効なメールアドレス形式で入力してください。')
    .build();

  inquiryForm.addTextItem()
    .setTitle('ご返信先メールアドレス')
    .setHelpText('運営からの返信を希望される場合のみご入力ください。')
    .setValidation(emailValidation)
    .setRequired(false);

  // ---------------------------------------------------------------------------
  // フォーム ②: 不在証明ページ 不適切コンテンツ通報フォーム（UGC 対策）
  // ---------------------------------------------------------------------------
  var reportForm = FormApp.create('雲隠れ（Kumogakure）不適切コンテンツの通報');
  reportForm.setDescription(
    '不在証明ページ（/s/...）に掲載されている表示名・メッセージについて、公序良俗違反・誹謗中傷・スパム等の問題がある場合はこちらからご報告ください。\n' +
    '確認のうえ、速やかに該当ページの削除および再発防止措置を行います。'
  );
  reportForm.setCollectEmail(false);
  reportForm.setAllowResponseEdits(false);
  reportForm.setLimitOneResponsePerUser(false);
  reportForm.setPublishingSummary(false);
  reportForm.setConfirmationMessage(
    'ご報告を受け付けました。内容を確認のうえ速やかに対応いたします。'
  );

  var sessionIdItem = reportForm.addTextItem()
    .setTitle('対象セッション ID')
    .setHelpText('報告対象の不在証明 ID（通常は自動で入力されます）')
    .setRequired(true);

  reportForm.addMultipleChoiceItem()
    .setTitle('通報理由')
    .setChoiceValues([
      '誹謗中傷・差別的表現・嫌がらせ',
      '個人情報（氏名・住所・電話番号等）の掲載',
      'スパム・営利宣伝・不審な URL',
      'その他、公序良俗・利用規約に反する内容'
    ])
    .setRequired(true);

  reportForm.addParagraphTextItem()
    .setTitle('補足詳細')
    .setHelpText('問題箇所の詳細があればご記入ください。')
    .setRequired(false);

  // 事前入力 URL テンプレートの生成
  var placeholder = 'SESSION_ID_PLACEHOLDER';
  var prefilledUrl = reportForm
    .createResponse()
    .withItemResponse(sessionIdItem.createResponse(placeholder))
    .toPrefilledUrl();
  var reportUrlTemplate = prefilledUrl.replace(placeholder, '{session_id}');
  var sampleTestUrl = reportUrlTemplate.replace('{session_id}', 'test123456');

  var lines = [
    '================================================================',
    '雲隠れ（Kumogakure）Google フォーム作成完了',
    '================================================================',
    '',
    '[フォーム ①] お問い合わせ・不具合報告',
    '  公開 URL (S-08 / Privacy / App Store 用): ' + inquiryForm.getPublishedUrl(),
    '  編集 URL (メール通知 ON 用):              ' + inquiryForm.getEditUrl(),
    '',
    '[フォーム ②] 不適切コンテンツ通報 (UGC)',
    '  公開 URL:                                ' + reportForm.getPublishedUrl(),
    '  編集 URL (メール通知 ON 用):              ' + reportForm.getEditUrl(),
    '  REPORT_FORM_URL_TEMPLATE:                ' + reportUrlTemplate,
    '  テスト用 URL (test123456 事前入力済):    ' + sampleTestUrl,
    '',
    '----------------------------------------------------------------',
    '次の操作（必須）:',
    '  1. 上記 2 つの「編集 URL」をブラウザで開く',
    '  2. 各フォームの「回答」タブ → 右上「⋮」→',
    '     「新しい回答についてのメール通知を受け取る」を ON にする',
    '  3. フォーム ① の公開 URL と フォーム ② のテスト用 URL から',
    '     1 回ずつ送信テストし、メール通知が届くことを確認する',
    '================================================================'
  ];

  var summary = lines.join('\n');
  Logger.log(summary);
  console.log(summary);
}
