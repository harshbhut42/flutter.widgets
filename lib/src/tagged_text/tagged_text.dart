// Copyright 2018 the Dart project authors.
//
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file or at
// https://developers.google.com/open-source/licenses/bsd

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';
import 'package:meta/meta.dart';

/// Builds a [TextSpan] with the provided [text].
typedef TextSpan TextSpanBuilder(String text);

/// Displays the provided [content] in a [RichText] after parsing and replacing
/// HTML tags using [tagToTextSpanBuilder].
///
/// This provides a convenient way to style localized text that is marked up
/// with semantic tags.
///
/// Refer to the README file in this package for more info.
class TaggedText extends StatefulWidget {
  /// The tagged content to render.
  final String content;

  /// A map of [TextSpanBuilder]s by lower-case HTML tag name. Tag names must be
  /// lower-case.
  ///
  /// This is used to determine how to render each tag that is found in
  /// [content].
  ///
  /// If a tag is missing, a warning will be printed and the text will be
  /// rendered in the default [style].
  ///
  /// Tags that are actual HTML tags (e.g., "link") are not allowed and will
  /// result in an assertion error being thrown.
  // TODO: Consider changing implementation to use a simpler HTML
  // parser. This would make the parsing faster and allow us to support HTML
  // tags without getting weird behavior (e.g., since link tags don't support
  // contents in an HTML document, the parser doesn't treat the contents as
  // being part of the element).
  final Map<String, TextSpanBuilder> tagToTextSpanBuilder;

  /// Default style to use for all spans of text.
  final TextStyle style;

  /// Horizontal alignment of the spans of text.
  ///
  /// See [RichText.textAlign].
  final TextAlign textAlign;

  /// The directionality of the text.
  ///
  /// See [RichText.textDirection].
  final TextDirection textDirection;

  /// The choice of whether the spans of text should break at soft line breaks
  ///
  /// See [RichText.softWrap].
  final bool softWrap;

  /// The manner in which to handle visual overflow of the spans of text.
  ///
  /// See [RichText.overflow].
  final TextOverflow overflow;

  /// The number of font pixels for each logical pixel.
  ///
  /// When null, this will default to [MediaQueryData.textScaleFactor] when
  /// available or 1.0.
  ///
  /// See [Text.textScaleFactor].
  final double textScaleFactor;

  /// An optional maximum number of lines for the spans of text.
  ///
  /// If they exceed the given number of lines, they will be truncated
  /// according to [overflow].
  ///
  /// See [RichText.maxLines].
  final int maxLines;

  /// Creates a new [TaggedText].
  ///
  /// For unspecified parameters, the defaults in [RichText] will be used.
  TaggedText(
      {Key key,
      @required this.content,
      @required this.tagToTextSpanBuilder,
      this.style,
      this.textAlign = TextAlign.start,
      this.textDirection,
      this.softWrap = true,
      this.overflow = TextOverflow.clip,
      this.textScaleFactor,
      this.maxLines})
      : assert(
            tagToTextSpanBuilder.keys.every((key) => key == key.toLowerCase())),
        assert(() {
          final htmlTags = Set.of([
            'a',
            'abbr',
            'acronym',
            'address',
            'applet',
            'area',
            'article',
            'aside',
            'audio',
            'b',
            'base',
            'basefont',
            'bdi',
            'bdo',
            'bgsound',
            'big',
            'blink',
            'blockquote',
            'body',
            'br',
            'button',
            'canvas',
            'caption',
            'center',
            'cite',
            'code',
            'col',
            'colgroup',
            'command',
            'content',
            'data',
            'datalist',
            'dd',
            'del',
            'details',
            'dfn',
            'dialog',
            'dir',
            'div',
            'dl',
            'dt',
            'element',
            'em',
            'embed',
            'fieldset',
            'figcaption',
            'figure',
            'font',
            'footer',
            'form',
            'frame',
            'frameset',
            'h1',
            'h2',
            'h3',
            'h4',
            'h5',
            'h6',
            'head',
            'header',
            'hgroup',
            'hr',
            'html',
            'i',
            'iframe',
            'image',
            'img',
            'input',
            'ins',
            'isindex',
            'kbd',
            'keygen',
            'label',
            'legend',
            'li',
            'link',
            'listing',
            'main',
            'map',
            'mark',
            'marquee',
            'menu',
            'menuitem',
            'meta',
            'meter',
            'multicol',
            'nav',
            'nextid',
            'nobr',
            'noembed',
            'noframes',
            'noscript',
            'object',
            'ol',
            'optgroup',
            'option',
            'output',
            'p',
            'param',
            'picture',
            'plaintext',
            'pre',
            'progress',
            'q',
            'rb',
            'rp',
            'rt',
            'rtc',
            'ruby',
            's',
            'samp',
            'script',
            'section',
            'select',
            'shadow',
            'slot',
            'small',
            'source',
            'spacer',
            'span',
            'strike',
            'strong',
            'style',
            'sub',
            'summary',
            'sup',
            'table',
            'tbody',
            'td',
            'template',
            'textarea',
            'tfoot',
            'th',
            'thead',
            'time',
            'title',
            'tr',
            'track',
            'tt',
            'u',
            'ul',
            'var',
            'video',
            'wbr',
            'xmp',
          ]);
          htmlTags.retainAll(tagToTextSpanBuilder.keys);
          return htmlTags.isEmpty;
        }(), 'Tags that are actual HTML tags are not allowed'),
        super(key: key);

  @override
  State<StatefulWidget> createState() => new _TaggedTextState();
}

/// [State] for [TaggedText].
class _TaggedTextState extends State<TaggedText> {
  bool _didParse;
  dom.Node _document;
  List<TextSpan> _textSpans;

  @override
  void initState() {
    super.initState();
    _parseContent();
    _parseSpans();
  }

  @override
  void didUpdateWidget(TaggedText oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.content != widget.content) {
      _parseContent();
      _parseSpans();
    } else if (!(const MapEquality()
        .equals(oldWidget.tagToTextSpanBuilder, widget.tagToTextSpanBuilder))) {
      _parseSpans();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_didParse) return new Container();
    assert(_textSpans != null);

    return new RichText(
        text: new TextSpan(children: _textSpans, style: widget.style),
        textAlign: widget.textAlign,
        textDirection: widget.textDirection,
        softWrap: widget.softWrap,
        overflow: widget.overflow,
        textScaleFactor: widget.textScaleFactor ??
            MediaQuery.of(context, nullOk: true)?.textScaleFactor ??
            1.0,
        maxLines: widget.maxLines);
  }

  void _parseContent() {
    try {
      final document = parse(widget.content);
      setState(() {
        _document = document.body;
        _didParse = true;
      });
    } on Exception catch (_) {
      assert(false);
      // Parse exceptions are not clearly documented.
      setState(() => _didParse = false);
    }
  }

  void _parseSpans() {
    if (!_didParse) return;

    _textSpans = _document.nodes
        .map((node) {
          if (node is dom.Text) {
            return new TextSpan(text: node.text);
          }

          if (node is! dom.Element) return null;
          final element = node as dom.Element;

          assert(element.children.isEmpty,
              'Tags should not be placed within tags.');

          // The parser always returns tag names as lower case.
          final textSpanBuilder =
              widget.tagToTextSpanBuilder[element.localName];

          assert(textSpanBuilder != null);
          if (textSpanBuilder == null) return new TextSpan(text: element.text);

          return textSpanBuilder(element.text);
        })
        .where((span) => span != null)
        .toList();
  }
}
