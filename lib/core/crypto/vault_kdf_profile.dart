enum VaultKdfProfile {
  argon2id64MiB(id: 1, memory: 65536, iterations: 3, parallelism: 4);

  const VaultKdfProfile({
    required this.id,
    required this.memory,
    required this.iterations,
    required this.parallelism,
  });
  final int id;
  final int memory;
  final int iterations;
  final int parallelism;
}
