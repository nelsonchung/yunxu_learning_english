enum SentenceLevel {
  kindergarten(
    '幼兒園',
    'Ages 3–6: concrete daily objects, very short sentences, about 3–6 words, simple present.',
  ),
  elementary(
    '國小',
    'Ages 6–12: familiar school and family situations, about 6–10 words, basic vocabulary and grammar.',
  ),
  juniorHigh(
    '國中',
    'Ages 12–15: daily situations, about 10–15 words, common tenses and simple clauses.',
  ),
  seniorHigh(
    '高中',
    'Ages 15–18: broader social topics, about 15–22 words, varied grammar and clauses.',
  ),
  university(
    '大學',
    'University learners: academic and abstract topics, nuanced vocabulary and complex sentences.',
  ),
  professional(
    '專業人士',
    'Adult professionals: realistic workplace or domain-specific situations, precise natural professional language.',
  );

  const SentenceLevel(this.label, this.guidance);
  final String label;
  final String guidance;
}
