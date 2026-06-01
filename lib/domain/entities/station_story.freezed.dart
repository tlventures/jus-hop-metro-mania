// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'station_story.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

StationStory _$StationStoryFromJson(Map<String, dynamic> json) {
  return _StationStory.fromJson(json);
}

/// @nodoc
mixin _$StationStory {
  String get id => throw _privateConstructorUsedError;
  String get stationName => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  String get imageUrl => throw _privateConstructorUsedError;
  List<StoryFrame> get frames => throw _privateConstructorUsedError;
  int get points => throw _privateConstructorUsedError;
  bool get isCompleted => throw _privateConstructorUsedError;

  /// Serializes this StationStory to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of StationStory
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $StationStoryCopyWith<StationStory> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $StationStoryCopyWith<$Res> {
  factory $StationStoryCopyWith(
    StationStory value,
    $Res Function(StationStory) then,
  ) = _$StationStoryCopyWithImpl<$Res, StationStory>;
  @useResult
  $Res call({
    String id,
    String stationName,
    String description,
    String imageUrl,
    List<StoryFrame> frames,
    int points,
    bool isCompleted,
  });
}

/// @nodoc
class _$StationStoryCopyWithImpl<$Res, $Val extends StationStory>
    implements $StationStoryCopyWith<$Res> {
  _$StationStoryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of StationStory
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? stationName = null,
    Object? description = null,
    Object? imageUrl = null,
    Object? frames = null,
    Object? points = null,
    Object? isCompleted = null,
  }) {
    return _then(
      _value.copyWith(
            id:
                null == id
                    ? _value.id
                    : id // ignore: cast_nullable_to_non_nullable
                        as String,
            stationName:
                null == stationName
                    ? _value.stationName
                    : stationName // ignore: cast_nullable_to_non_nullable
                        as String,
            description:
                null == description
                    ? _value.description
                    : description // ignore: cast_nullable_to_non_nullable
                        as String,
            imageUrl:
                null == imageUrl
                    ? _value.imageUrl
                    : imageUrl // ignore: cast_nullable_to_non_nullable
                        as String,
            frames:
                null == frames
                    ? _value.frames
                    : frames // ignore: cast_nullable_to_non_nullable
                        as List<StoryFrame>,
            points:
                null == points
                    ? _value.points
                    : points // ignore: cast_nullable_to_non_nullable
                        as int,
            isCompleted:
                null == isCompleted
                    ? _value.isCompleted
                    : isCompleted // ignore: cast_nullable_to_non_nullable
                        as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$StationStoryImplCopyWith<$Res>
    implements $StationStoryCopyWith<$Res> {
  factory _$$StationStoryImplCopyWith(
    _$StationStoryImpl value,
    $Res Function(_$StationStoryImpl) then,
  ) = __$$StationStoryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String stationName,
    String description,
    String imageUrl,
    List<StoryFrame> frames,
    int points,
    bool isCompleted,
  });
}

/// @nodoc
class __$$StationStoryImplCopyWithImpl<$Res>
    extends _$StationStoryCopyWithImpl<$Res, _$StationStoryImpl>
    implements _$$StationStoryImplCopyWith<$Res> {
  __$$StationStoryImplCopyWithImpl(
    _$StationStoryImpl _value,
    $Res Function(_$StationStoryImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of StationStory
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? stationName = null,
    Object? description = null,
    Object? imageUrl = null,
    Object? frames = null,
    Object? points = null,
    Object? isCompleted = null,
  }) {
    return _then(
      _$StationStoryImpl(
        id:
            null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                    as String,
        stationName:
            null == stationName
                ? _value.stationName
                : stationName // ignore: cast_nullable_to_non_nullable
                    as String,
        description:
            null == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                    as String,
        imageUrl:
            null == imageUrl
                ? _value.imageUrl
                : imageUrl // ignore: cast_nullable_to_non_nullable
                    as String,
        frames:
            null == frames
                ? _value._frames
                : frames // ignore: cast_nullable_to_non_nullable
                    as List<StoryFrame>,
        points:
            null == points
                ? _value.points
                : points // ignore: cast_nullable_to_non_nullable
                    as int,
        isCompleted:
            null == isCompleted
                ? _value.isCompleted
                : isCompleted // ignore: cast_nullable_to_non_nullable
                    as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$StationStoryImpl implements _StationStory {
  const _$StationStoryImpl({
    required this.id,
    required this.stationName,
    required this.description,
    required this.imageUrl,
    required final List<StoryFrame> frames,
    required this.points,
    this.isCompleted = false,
  }) : _frames = frames;

  factory _$StationStoryImpl.fromJson(Map<String, dynamic> json) =>
      _$$StationStoryImplFromJson(json);

  @override
  final String id;
  @override
  final String stationName;
  @override
  final String description;
  @override
  final String imageUrl;
  final List<StoryFrame> _frames;
  @override
  List<StoryFrame> get frames {
    if (_frames is EqualUnmodifiableListView) return _frames;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_frames);
  }

  @override
  final int points;
  @override
  @JsonKey()
  final bool isCompleted;

  @override
  String toString() {
    return 'StationStory(id: $id, stationName: $stationName, description: $description, imageUrl: $imageUrl, frames: $frames, points: $points, isCompleted: $isCompleted)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StationStoryImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.stationName, stationName) ||
                other.stationName == stationName) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.imageUrl, imageUrl) ||
                other.imageUrl == imageUrl) &&
            const DeepCollectionEquality().equals(other._frames, _frames) &&
            (identical(other.points, points) || other.points == points) &&
            (identical(other.isCompleted, isCompleted) ||
                other.isCompleted == isCompleted));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    stationName,
    description,
    imageUrl,
    const DeepCollectionEquality().hash(_frames),
    points,
    isCompleted,
  );

  /// Create a copy of StationStory
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StationStoryImplCopyWith<_$StationStoryImpl> get copyWith =>
      __$$StationStoryImplCopyWithImpl<_$StationStoryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$StationStoryImplToJson(this);
  }
}

abstract class _StationStory implements StationStory {
  const factory _StationStory({
    required final String id,
    required final String stationName,
    required final String description,
    required final String imageUrl,
    required final List<StoryFrame> frames,
    required final int points,
    final bool isCompleted,
  }) = _$StationStoryImpl;

  factory _StationStory.fromJson(Map<String, dynamic> json) =
      _$StationStoryImpl.fromJson;

  @override
  String get id;
  @override
  String get stationName;
  @override
  String get description;
  @override
  String get imageUrl;
  @override
  List<StoryFrame> get frames;
  @override
  int get points;
  @override
  bool get isCompleted;

  /// Create a copy of StationStory
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StationStoryImplCopyWith<_$StationStoryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

StoryFrame _$StoryFrameFromJson(Map<String, dynamic> json) {
  return _StoryFrame.fromJson(json);
}

/// @nodoc
mixin _$StoryFrame {
  String get id => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  String get imageUrl => throw _privateConstructorUsedError;
  int get order => throw _privateConstructorUsedError;

  /// Serializes this StoryFrame to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of StoryFrame
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $StoryFrameCopyWith<StoryFrame> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $StoryFrameCopyWith<$Res> {
  factory $StoryFrameCopyWith(
    StoryFrame value,
    $Res Function(StoryFrame) then,
  ) = _$StoryFrameCopyWithImpl<$Res, StoryFrame>;
  @useResult
  $Res call({
    String id,
    String title,
    String content,
    String imageUrl,
    int order,
  });
}

/// @nodoc
class _$StoryFrameCopyWithImpl<$Res, $Val extends StoryFrame>
    implements $StoryFrameCopyWith<$Res> {
  _$StoryFrameCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of StoryFrame
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? content = null,
    Object? imageUrl = null,
    Object? order = null,
  }) {
    return _then(
      _value.copyWith(
            id:
                null == id
                    ? _value.id
                    : id // ignore: cast_nullable_to_non_nullable
                        as String,
            title:
                null == title
                    ? _value.title
                    : title // ignore: cast_nullable_to_non_nullable
                        as String,
            content:
                null == content
                    ? _value.content
                    : content // ignore: cast_nullable_to_non_nullable
                        as String,
            imageUrl:
                null == imageUrl
                    ? _value.imageUrl
                    : imageUrl // ignore: cast_nullable_to_non_nullable
                        as String,
            order:
                null == order
                    ? _value.order
                    : order // ignore: cast_nullable_to_non_nullable
                        as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$StoryFrameImplCopyWith<$Res>
    implements $StoryFrameCopyWith<$Res> {
  factory _$$StoryFrameImplCopyWith(
    _$StoryFrameImpl value,
    $Res Function(_$StoryFrameImpl) then,
  ) = __$$StoryFrameImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String title,
    String content,
    String imageUrl,
    int order,
  });
}

/// @nodoc
class __$$StoryFrameImplCopyWithImpl<$Res>
    extends _$StoryFrameCopyWithImpl<$Res, _$StoryFrameImpl>
    implements _$$StoryFrameImplCopyWith<$Res> {
  __$$StoryFrameImplCopyWithImpl(
    _$StoryFrameImpl _value,
    $Res Function(_$StoryFrameImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of StoryFrame
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? content = null,
    Object? imageUrl = null,
    Object? order = null,
  }) {
    return _then(
      _$StoryFrameImpl(
        id:
            null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                    as String,
        title:
            null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                    as String,
        content:
            null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                    as String,
        imageUrl:
            null == imageUrl
                ? _value.imageUrl
                : imageUrl // ignore: cast_nullable_to_non_nullable
                    as String,
        order:
            null == order
                ? _value.order
                : order // ignore: cast_nullable_to_non_nullable
                    as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$StoryFrameImpl implements _StoryFrame {
  const _$StoryFrameImpl({
    required this.id,
    required this.title,
    required this.content,
    required this.imageUrl,
    required this.order,
  });

  factory _$StoryFrameImpl.fromJson(Map<String, dynamic> json) =>
      _$$StoryFrameImplFromJson(json);

  @override
  final String id;
  @override
  final String title;
  @override
  final String content;
  @override
  final String imageUrl;
  @override
  final int order;

  @override
  String toString() {
    return 'StoryFrame(id: $id, title: $title, content: $content, imageUrl: $imageUrl, order: $order)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StoryFrameImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.imageUrl, imageUrl) ||
                other.imageUrl == imageUrl) &&
            (identical(other.order, order) || other.order == order));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, title, content, imageUrl, order);

  /// Create a copy of StoryFrame
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StoryFrameImplCopyWith<_$StoryFrameImpl> get copyWith =>
      __$$StoryFrameImplCopyWithImpl<_$StoryFrameImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$StoryFrameImplToJson(this);
  }
}

abstract class _StoryFrame implements StoryFrame {
  const factory _StoryFrame({
    required final String id,
    required final String title,
    required final String content,
    required final String imageUrl,
    required final int order,
  }) = _$StoryFrameImpl;

  factory _StoryFrame.fromJson(Map<String, dynamic> json) =
      _$StoryFrameImpl.fromJson;

  @override
  String get id;
  @override
  String get title;
  @override
  String get content;
  @override
  String get imageUrl;
  @override
  int get order;

  /// Create a copy of StoryFrame
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StoryFrameImplCopyWith<_$StoryFrameImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
