enum AiProvider {
  openai,
  claude;

  String get label => this == openai ? 'OpenAI' : 'Claude';
  String get textModel => this == openai ? 'gpt-5.4-mini' : 'claude-sonnet-4-6';
}
