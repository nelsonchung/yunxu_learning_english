import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/learning_image.dart';
import '../../domain/models/word_card.dart';
import '../state/learning_image_notifier.dart';
import '../state/words_notifier.dart';
import '../widgets/ai_learning_image_settings.dart';
import '../widgets/image_preview.dart';
import 'learning_image_history_page.dart';

class LearningImagePage extends StatefulWidget {
  const LearningImagePage({super.key, required this.initialWord});
  final WordCard initialWord;
  @override
  State<LearningImagePage> createState() => _LearningImagePageState();
}

class _LearningImagePageState extends State<LearningImagePage> {
  bool _applying = false;
  String? _applyError;

  Future<void> _apply(LearningImageNotifier ai) async {
    final snapshot = ai.sourceWord;
    final bytes = ai.imageBytes;
    if (snapshot == null || bytes == null) return;
    final words = context.read<WordsNotifier>();
    final latest = words.findById(snapshot.id);
    if (latest == null) {
      setState(() => _applyError = '單字已刪除，無法套用圖片');
      return;
    }
    if (latest.word != snapshot.word ||
        latest.meaning != snapshot.meaning ||
        latest.memoryHint != snapshot.memoryHint ||
        latest.partsOfSpeechLabel != snapshot.partsOfSpeechLabel ||
        latest.sentences.join('\n') != snapshot.sentences.join('\n')) {
      ai.discard();
      setState(() => _applyError = '單字內容已變更，請核對並生成最新內容');
      return;
    }
    var replace = false;
    if (latest.imageCleared != snapshot.imageCleared ||
        latest.imagePath != snapshot.imagePath ||
        !_sameBytes(latest.imageBytes, snapshot.imageBytes)) {
      replace =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('圖片已變更'),
              content: const Text('等待期間已新增或替換圖片，仍要使用這張 AI 圖片嗎？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('保留目前圖片'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('替換圖片'),
                ),
              ],
            ),
          ) ??
          false;
      if (!replace || !mounted) return;
    }
    if (!ai.beginApply()) return;
    setState(() {
      _applying = true;
      _applyError = null;
    });
    try {
      await words.updateWordImage(
        snapshot.id,
        bytes,
        expectedCard: snapshot,
        allowImageReplacement: replace,
      );
      final saved = words.findById(snapshot.id);
      if (saved?.imagePath != null) {
        try {
          await ai.saveMetadata(
            wordId: snapshot.id,
            imageIdentity: path.basename(saved!.imagePath!),
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('圖片已儲存，但來源資訊保存失敗')));
          }
        }
      }
      ai.endApply();
      ai.discard();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _applyError = '圖片套用失敗：$e');
    } finally {
      ai.endApply();
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _generate(LearningImageNotifier ai) async {
    if (ai.content != null) {
      await ai.regenerate();
      return;
    }
    final words = context.read<WordsNotifier?>();
    final latest = words == null
        ? widget.initialWord
        : words.findById(widget.initialWord.id);
    if (latest == null) {
      setState(() => _applyError = '單字已刪除，無法生成圖片');
      return;
    }
    setState(() => _applyError = null);
    await ai.start(latest);
  }

  bool _sameBytes(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<LearningImageNotifier>();
    final differentWord =
        ai.sourceWord != null && ai.sourceWord!.id != widget.initialWord.id;
    return PopScope(
      canPop: !_applying,
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.initialWord.word} 學習小誌')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '預估約 NT\$3～5／張。台幣以 US\$1＝NT\$32 的預算匯率換算；實際費用依 API 用量與費率計算。',
            ),
            const SizedBox(height: 12),
            Text(
              '依實際用量計算的累計費用：US\$${ai.knownCostUsd.toStringAsFixed(4)}（約 NT\$${(ai.knownCostUsd * 32).toStringAsFixed(2)}）',
            ),
            Text(
              '本次已知費用：US\$${ai.currentCostUsd.toStringAsFixed(4)}${ai.currentHasUnknownCost ? '（含未知費用）' : ''}',
            ),
            if (ai.hasUnknownCost) const Text('部分請求費用未知；已送出的取消或逾時請求仍可能計費。'),
            TextButton.icon(
              onPressed: _applying
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const LearningImageHistoryPage(),
                      ),
                    ),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('查看 AI 費用紀錄'),
            ),
            const SizedBox(height: 16),
            if (!ai.canGenerateImage) ...[
              Text(
                !ai.hasKey
                    ? '請先在此裝置設定 ${ai.provider.label} API Key'
                    : '圖片生成需要另外設定 OpenAI API Key',
              ),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AiLearningImageSettingsPage(),
                  ),
                ),
                child: const Text('設定 API Key'),
              ),
            ] else if (differentWord) ...[
              Text('另有「${ai.sourceWord!.word}」的生成工作或預覽，請先完成或放棄。'),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        LearningImagePage(initialWord: ai.sourceWord!),
                  ),
                ),
                child: const Text('查看目前生成工作'),
              ),
            ] else ...[
              if (ai.isBusy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  ai.stage == LearningImageStage.researching
                      ? '正在上網核對單字內容'
                      : '正在生成圖片',
                ),
                if (!ai.isApplying)
                  TextButton(onPressed: ai.cancel, child: const Text('取消生成')),
              ],
              if (ai.stage == LearningImageStage.conflict) ...[
                const Text('核對內容與目前單字有明顯差異。選擇只影響圖卡，不會更改單字文字。'),
                const SizedBox(height: 8),
                Text('目前中文：${widget.initialWord.meaning}'),
                Text('差異：${ai.content?.conflict ?? ''}'),
                Text('核對中文：${ai.content?.meaning ?? ''}'),
                Text('核對例句：${ai.content?.sentences.join('\n') ?? ''}'),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => ai.resolveConflict(useExisting: true),
                      child: const Text('使用目前內容'),
                    ),
                    FilledButton(
                      onPressed: () => ai.resolveConflict(useExisting: false),
                      child: const Text('使用核對內容'),
                    ),
                  ],
                ),
              ],
              if (ai.error != null)
                Text(
                  ai.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (ai.imageBytes != null) ...[
                const SizedBox(height: 16),
                ImagePreview(
                  imageFile: null,
                  imageBytes: ai.imageBytes,
                  height: 480,
                  enableZoom: true,
                ),
                const Text('點擊圖片放大，確認中英文與圖解正確後再套用。'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: ai.isBusy || _applying ? null : () => _apply(ai),
                  child: Text(_applying ? '正在儲存' : '使用這張圖片'),
                ),
              ],
              if (_applyError != null)
                Text(
                  _applyError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (!ai.isBusy && ai.stage != LearningImageStage.conflict) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _applying ? null : () => _generate(ai),
                  child: Text(ai.content == null ? '核對並生成圖片' : '重新生成圖片（再次計費）'),
                ),
                if (ai.sourceWord != null)
                  TextButton(
                    onPressed: _applying
                        ? null
                        : () {
                            ai.discard();
                            Navigator.pop(context);
                          },
                    child: const Text('放棄圖片'),
                  ),
              ],
              if (ai.sources.isNotEmpty) ...[
                const Divider(),
                const Text('參考來源'),
                ...ai.sources.map(
                  (source) => TextButton(
                    onPressed: () =>
                        openLearningImageSource(context, source.url),
                    child: Text(source.title),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> openLearningImageSource(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法開啟參考來源')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法開啟參考來源')));
    }
  }
}
