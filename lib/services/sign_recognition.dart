// Contract for the future native CameraX/MediaPipe integration. No mock predictions.
abstract interface class SignRecognitionService {
  Future<bool> isAvailable();
  Stream<SignPrediction> get predictions;
  Future<void> start();
  Future<void> stop();
}

class SignPrediction {
  const SignPrediction({required this.text, required this.confidence});
  final String text;
  final double confidence;
}

abstract interface class SigningAvatarService {
  Future<bool> supportsPhrase(String text);
  Future<void> playPhrase(String text);
  Future<void> stop();
}
