library category_item;

import 'dart:async';
import 'dart:html';

import 'package:dartdoc_viewer/data.dart';
import 'package:dartdoc_viewer/read_yaml.dart';
import 'package:web_ui/web_ui.dart';

// TODO(tmandel): Don't hardcode in a path if it can be avoided.
const docsPath = '../../docs/';

/**
 * Anything that holds values and can be displayed.
 */
@observable 
class Container {
  String name;
  String comment = '<span></span>';
  
  Container(this.name, [this.comment]);
}

// Wraps a comment in span element to make it a single HTML Element.
String _wrapComment(String comment) {
  if (comment == null) comment = '';
  return '<span>$comment</span>';
}

/**
 * A [Container] that contains other [Container]s to be displayed.
 */
class Category extends Container {
  
  List<Container> content = [];
  
  Category.forClasses(Map yaml) : super('Classes') {
    yaml.keys.forEach((key) => content.add(new Class(yaml[key])));
  }
  
  Category.forVariables(Map yaml) : super('Variables') {
    yaml.keys.forEach((key) => content.add(new Variable(yaml[key])));
  }
  
  Category.forFunctions(Map yaml, String name) : super(name) {
    yaml.keys.forEach((key) => content.add(new Method(yaml[key])));
  }
}

/**
 * A [Container] synonymous with a page.
 */
class Item extends Container {
  /// A list of [Item]s representing the path to this [Item].
  List<Item> path = [];
  
  Item(String name, [String comment]) : super(name, comment);
  
  /// [Item]'s name with its properties properly appended. 
  String get decoratedName => name;
}

/**
 * An [Item] with no content. This is used to facilitate lazy loading.
 */
class Placeholder extends Item {
  
  /// The path to the file with the real data relative to [docsPath].
  String location;
  
  Placeholder(String name, this.location) : super(name);
}

/**
 * An [Item] containing all of the [Library] and [Placeholder] objects.
 */
class Home extends Item {
  
  /// All libraries being viewed from the homepage.
  List<Item> libraries;
  
  /// The constructor parses the [libraries] input and constructs
  /// [Placeholder] objects to display before loading libraries.
  Home(List libraries) : super('Dart API Reference') {
    this.libraries = [];
    for (String library in libraries) {
      var libraryName = library.replaceAll('.yaml', '');
      libraryNames[libraryName] = libraryName.replaceAll('.', '-');
      this.libraries.add(new Placeholder(libraryName, library));
    };
  }
  
  /// Loads the library's data and returns a [Future] for external handling.
  Future loadLibrary(Placeholder place) {
    var data = retrieveFileContents('$docsPath${place.location}');
    return data.then((response) {
      var lib = loadData(response);
      var index = libraries.indexOf(place);
      buildHierarchy(lib, lib);
      libraries.remove(place);
      libraries.insert(index, lib);
      return lib;
    });
  }
  
  /// Checks if [library] is defined in [libraries].
  bool contains(String library) => libraryNames.values.contains(library);
  
  /// Returns the [Item] representing [libraryName].
  // TODO(tmandel): Stop looping through 'libraries' so much. Possibly use a 
  // map from library names to their objects.
  Item itemNamed(String libraryName) {
    return libraries.firstWhere((lib) => libraryNames[lib.name] == libraryName,
        orElse: () => null);
  }
}


/// Runs through the member structure and creates path information.
void buildHierarchy(Item page, Item previous) {
  page.path
    ..addAll(previous.path)
    ..add(page);
  if (page is Library || page is Class) {
    if (page.functions != null) {
      page.functions.content.forEach((method) {
        buildHierarchy(method, page);
      });
    }
    if (page is Library) {
      if (page.classes != null) {
        page.classes.content.forEach((clazz) {
          buildHierarchy(clazz, page);
        });
      }
    }
  }
}

/**
 * An [Item] that describes a single Dart library.
 */
class Library extends Item {
  
  Category classes;
  Category variables;
  Category functions;
  
  Library(Map yaml) : super(yaml['name'], _wrapComment(yaml['comment'])) {
    if (yaml['classes'] != null) {
      classes = new Category.forClasses(yaml['classes']);
    }
    if (yaml['variables'] != null) {
      variables = new Category.forVariables(yaml['variables']);
    }
    if (yaml['functions'] != null) {
      functions = new Category.forFunctions(yaml['functions'], 'Functions');
    }
  }
  
  String get decoratedName => "library $name";
}

/**
 * An [Item] that describes a single Dart class.
 */
class Class extends Item {
  
  Category functions;
  Category variables;
  
  LinkableType superClass;
  bool isAbstract;
  bool isTypedef;
  List<LinkableType> implements;
  
  Class(Map yaml) : super(yaml['name'], _wrapComment(yaml['comment'])) {
    if (yaml['variables'] != null) {
      variables = new Category.forVariables(yaml['variables']);
    }
    if (yaml['methods'] != null) {
      functions = new Category.forFunctions(yaml['methods'], 'Methods');
    }
    this.superClass = new LinkableType(yaml['superclass']);
    this.isAbstract = yaml['abstract'] == 'true';
    this.isTypedef = yaml['typedef'] == 'true';
    this.implements = yaml['implements'] == null ? [] :
        yaml['implements'].map((item) => new LinkableType(item)).toList();
  }
  
  String get decoratedName => isAbstract ? 'abstract class ${this.name}' :
    isTypedef ? 'typedef ${this.name}' : 'class ${this.name}';
}

/**
 * An [Item] that describes a single Dart method.
 */
class Method extends Item {
  
  bool isStatic;
  LinkableType type;
  List<Parameter> parameters;
  
  Method(Map yaml) : super(yaml['name'], _wrapComment(yaml['comment'])) {
    this.isStatic = yaml['static'] == 'true';
    this.type = new LinkableType(yaml['return']);
    this.parameters = _getParameters(yaml['parameters']);
  }
  
  /// Creates [Parameter] objects for each parameter to this method.
  List<Parameter> _getParameters(Map parameters) {
    var values = [];
    if (parameters != null) {
      parameters.forEach((name, data) {
        values.add(new Parameter(name, data));
      });
    }
    return values;
  }
  
  String get decoratedName => isStatic ? 'static $name' : name;
}

/**
 * A single parameter to a [Method].
 */
class Parameter {
  
  String name;
  bool isOptional;
  bool isNamed;
  bool hasDefault;
  LinkableType type;
  String defaultValue;
  
  Parameter(this.name, Map yaml) {
    this.isOptional = yaml['optional'] == 'true';
    this.isNamed = yaml['named'] == 'true';
    this.hasDefault = yaml['default'] == 'true';
    this.type = new LinkableType(yaml['type']);
    this.defaultValue = yaml['value'];
  }
  
  String get decoratedName {
    var decorated = name;
    if (hasDefault) {
      if (isNamed) {
        decorated = '$decorated: $defaultValue';
      } else {
        decorated = '$decorated=$defaultValue';
      }
    }
    return decorated;
  }
}

/**
 * A [Container] that describes a single Dart variable.
 */
class Variable extends Container {
  
  bool isFinal;
  bool isStatic;
  LinkableType type;
  
  Variable(Map yaml) : super(yaml['name'], _wrapComment(yaml['comment'])) {
    this.isFinal = yaml['final'] == 'true';
    this.isStatic = yaml['static'] == 'true';
    this.type = new LinkableType(yaml['type']);
  }
  
  /// The attributes of this variable to be displayed before it.
  String get prefix {
    var prefix = isStatic ? 'static ' : '';
    return isFinal ? '${prefix}final' : prefix;
  }
}

/**
 * A Dart type that should link to other [Item]s.
 */
class LinkableType {

  /// The resolved qualified name of the type this [LinkableType] represents.
  String type;
  
  /// The constructor resolves the library name by finding the correct library
  /// from [libraryNames] and changing [type] to match.
  LinkableType(String type) {
    var current = type;
    this.type;
    while (this.type == null) {
      if (libraryNames[current] != null) {
        this.type = type.replaceFirst(current, libraryNames[current]);
      } else {
        var index = current.lastIndexOf('.');
        if (index == -1) this.type = type;
        current = index != -1 ? current.substring(0, index) : '';
      }
    }
  }

  /// The simple name for this type.
  String get simpleType => this.type.split('.').last;

  /// The [Item] describing this type if it has been loaded, otherwise null.
  List<String> get location => type.split('.');
}