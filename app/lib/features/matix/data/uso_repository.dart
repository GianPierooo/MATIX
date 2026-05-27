import '../../../api/matix_client.dart';

/// Snapshot del medidor de uso de OpenAI (Capa 2 Paso 5).
///
/// Lo devuelve `GET /api/v1/matix/uso`. Es consumo acumulado desde
/// que arrancó el cerebro — no es un saldo restante. Si el cerebro
/// se reinicia, vuelve a cero (ver `cerebro/app/matix/uso.py` para
/// la decisión de no persistir).
class UsoSnapshot {
  const UsoSnapshot({
    required this.promptTokens,
    required this.cachedPromptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.llamadasChat,
    required this.segundosWhisper,
    required this.llamadasWhisper,
    required this.costoUsd,
  });

  final int promptTokens;
  final int cachedPromptTokens;
  final int completionTokens;
  final int totalTokens;
  final int llamadasChat;
  final double segundosWhisper;
  final int llamadasWhisper;
  final double costoUsd;

  factory UsoSnapshot.fromJson(Map<String, dynamic> j) => UsoSnapshot(
        promptTokens: (j['prompt_tokens'] as num).toInt(),
        cachedPromptTokens: (j['cached_prompt_tokens'] as num).toInt(),
        completionTokens: (j['completion_tokens'] as num).toInt(),
        totalTokens: (j['total_tokens'] as num).toInt(),
        llamadasChat: (j['llamadas_chat'] as num).toInt(),
        segundosWhisper: (j['segundos_whisper'] as num).toDouble(),
        llamadasWhisper: (j['llamadas_whisper'] as num).toInt(),
        costoUsd: (j['costo_usd'] as num).toDouble(),
      );

  bool get vacio => totalTokens == 0 && segundosWhisper == 0;
}

class UsoRepository {
  UsoRepository(this._client);
  final MatixClient _client;

  Future<UsoSnapshot> obtener() async {
    final j = await _client.getOne('/api/v1/matix/uso');
    return UsoSnapshot.fromJson(j);
  }
}
