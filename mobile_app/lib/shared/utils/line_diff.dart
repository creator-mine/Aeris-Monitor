class DiffLine {
  final String prefix;
  final String text;

  const DiffLine(this.prefix, this.text);
}

/// Simple LCS-based line diff. Returns lines prefixed with '+', '-' or ' '.
List<DiffLine> diffLines(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;

  final dp = List.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
    growable: false,
  );

  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = (a[i] == b[j])
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }

  final result = <DiffLine>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      result.add(DiffLine(' ', a[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      result.add(DiffLine('-', a[i]));
      i++;
    } else {
      result.add(DiffLine('+', b[j]));
      j++;
    }
  }
  while (i < n) {
    result.add(DiffLine('-', a[i]));
    i++;
  }
  while (j < m) {
    result.add(DiffLine('+', b[j]));
    j++;
  }

  return result;
}