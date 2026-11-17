// ignore_for_file: unused_element, unused_field
export 'src/hidden.dart' show Shown;

class Shape {
  void _forget() => _cache = 0;
  String describe({bool short = false}) => name;
  int get area => sides;

  int _cache = 0;
  late String label;
  int sides;
  final String name;

  static int count() => 0;
  static const int corners = 0;

  factory Shape.square() => Shape('square', sides: 4);
  Shape(this.name, {required this.sides});
}

class _Hidden {}

class Unit {
  const Unit();
}

enum Side { left, right }

typedef Measure = int Function(String text);

int twice(int value) => value * 2;

const answer = 42;
