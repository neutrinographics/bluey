// ignore_for_file: unused_element, unused_field
export 'src/hidden.dart' show Shown;

const answer = 42;

int twice(int value) => value * 2;

typedef Measure = int Function(String text);

enum Side { left, right }

class Shape {
  Shape(this.name, {required this.sides});
  factory Shape.square() => Shape('square', sides: 4);

  static const int corners = 0;
  static int count() => 0;

  final String name;
  int sides;
  late String label;
  int _cache = 0;

  int get area => sides;
  String describe({bool short = true}) => name;
  void _forget() => _cache = 0;
}

class Unit {
  const Unit();
}

class _Hidden {}
