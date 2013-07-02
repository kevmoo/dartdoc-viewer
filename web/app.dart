/**
 * This application displays documentation generated by the docgen tool
 * found at dart-repo/dart/pkg/docgen. 
 * 
 * The Yaml file outputted by the docgen tool will be read in to 
 * generate [Page] and [Category] and [CompositeContainer]. 
 * Pages, Categories and CategoryItems are used to format and layout the page.
 */
// TODO(janicejl): Add a link to the dart docgen landing page in future. 
library dartdoc_viewer;

import 'dart:html';
import 'package:web_ui/web_ui.dart';
import 'package:dartdoc_viewer/data.dart';
import 'package:dartdoc_viewer/item.dart';
import 'package:dartdoc_viewer/read_yaml.dart';

// The page pathname at first load for navigation.
String origin;

// TODO(janicejl): YAML path should not be hardcoded. 
// Path to the YAML file being read in. 
const sourcePath = '../../docs/library_list.txt';

// Function to set the title of the current page. 
String get title => currentPage == null ? '' : currentPage.decoratedName;

// The correct comment for the current page.
String get comment => currentPage != null ? currentPage.comment : '';

// The homepage from which every [Item] can be reached.
@observable Item homePage;

// The current page being shown.
@observable Item currentPage;

/**
 * Changes the currentPage to the page of the item clicked
 * without pushing state onto the history.
 */
changePageWithoutState(Item page) {
  if (page != null) {
    currentPage = page;
    update();
  }
}

/// Replaces a [PlaceHolder] with a [Library] in [homePage]'s content.
Library _updateContent(String data, PlaceHolder page) {
  var lib = loadData(data);
  var index = homePage.content.indexOf(page);
  homePage.content.remove(page);
  homePage.content.insert(index, lib);
  buildHierarchy(lib, homePage);
  return lib;
}

/**
 * Pushes state onto the history before updating the [currentPage].                                                                                                                                          
 */
changePage(Item page) {
  if (page is PlaceHolder) {
    var data = page.loadLibrary();
    data.then((response) {
      var lib = _updateContent(response, page);
      changePage(lib);
    });
  } else if (page != null && currentPage != page) {
    var state = page.path;
    var title = 'Dart API Reference';
    var url = origin;
    if (state != '') {
      var title = state.substring(0, state.length - 1);
      url = '$origin#$state';
    } else {
      url = '${origin}index.html';
    }
    window.history.pushState(state, title, url);
  }
  changePageWithoutState(page);
}

/**
 * Creates a list of [Item] objects from the [path] describing the
 * path to a particular [Item] object.
 */
List<Item> getBreadcrumbs(String path) {
  // Matches alphanumeric variable/method names ending with a '/'.  
  var regex = new RegExp(r'(_?([a-zA-Z0-9_%]+)=?)/');
  var matches = regex.allMatches(path);
  var currentPath = '';
  var breadcrumbs = [homePage];
  matches.forEach((match) {
    currentPath = '$currentPath${match.group(0)}';
    breadcrumbs.add(pageIndex[currentPath]);
  });
  return breadcrumbs;
}

/// Adds the correct interfaces to [postDescriptor].
void _updateInheritance(Element postDescriptor) {
  var interfaces = currentPage.implements;
  var paragraph = new ParagraphElement();
  if (!interfaces.isEmpty) {
    paragraph.appendText("Implements: ");
  }
  interfaces.forEach((element) {
    paragraph.append(_getType(element));
    if (element != interfaces.last) {
      paragraph.appendText(", ");
    } else {
      paragraph.appendHtml("<br/>");
    }
  }); 
  paragraph.appendText("Extends: ");
  paragraph.append(_getType(currentPage.superClass));
  postDescriptor.children.add(paragraph);
}

/// Generates an HTML [Element] given a [LinkableType].
// TODO(tmandel): Add a CSS class or use a different tag if the link isn't
// resolved so that it isn't displayed with the same CSS as a working link.
Element _getType(LinkableType type) {
  var link = new Element.html("<a>${type.simpleType}</a>")
    ..onClick.listen((_) => handleLink(type));
  return link;
}

/// Handles lazy loading of libraries from links not on the homepage.                                                                                                                                      
void handleLink(LinkableType type) {
  if (type.location != null) {
    changePage(type.location);
  } else {
    homePage.content.forEach((element) {
      if (element is PlaceHolder) {
        var betterName = libraryNames[element.name];
        if (type.type.startsWith(betterName)) {
          element.loadLibrary().then((response) {
            _updateContent(response, element);
            changePage(type.location);
          });
        }
      }
    });
  }
}

/// Adds a single parameter to [postData].
void _addParameter(Parameter parameter, Element postData) {
  postData.append(_getType(parameter.type));
  postData.appendText(' ${parameter.decoratedName}');
}

/// Adds the correct parameters to [postDescriptor].
void _updateParameters(Element postDescriptor) {
  var required = currentPage.parameters.where((item) => !item.isOptional);
  var optional = currentPage.parameters.where((item) => item.isOptional);
  var postData = new ParagraphElement()
    ..appendText('(');
  required.forEach((parameter) {
    _addParameter(parameter, postData);
    if (parameter != required.last || !optional.isEmpty) {
      postData.appendText(', ');
    }
  });
  if (!optional.isEmpty) {
    optional.first.isNamed ? 
        postData.appendText('{') : postData.appendText('[');
    optional.forEach((parameter) {
      _addParameter(parameter, postData);
      if (parameter != optional.last) postData.appendText(', ');
    });
    optional.first.isNamed ? 
        postData.appendText('}') : postData.appendText(']');
  }
  postData.appendText(')');
  postDescriptor.children.add(postData);
}

/// Adds the correct comment to [description].
void _updateComment() {
  var description = query('.description');
  description.children.clear();
  if (currentPage.comment != null && currentPage.comment != '') {
    description.children.add(new Element.html(currentPage.comment));
  }
}

/**
 * Update the comment and descriptor tags to match the current page.
 */
void update() {
  _updateComment();
  // TODO(tmandel): Use custom elements to avoid this querying.
  var descriptors = queryAll('.descriptor');
  var preDescriptor = descriptors[0];
  var postDescriptor = descriptors[1];
  preDescriptor.children.clear();
  postDescriptor.children.clear();
  if (currentPage is Method) {
    preDescriptor.children.add(_getType(currentPage.type));
    _updateParameters(postDescriptor);
  } else if (currentPage is Class) {
    _updateInheritance(postDescriptor);
  }
}

// Builds homepage and sets up listener for browser navigation.                                                                                                                                                                           
main() {
  // Remove 'index.html' suffix for easier navigation.
  origin = window.location.pathname.replaceAll('index.html', '');
  var manifest = retrieveFileContents(sourcePath);
  manifest.then((response) {
    var libraries = response.split('\n');
    currentPage = new Home(libraries);
    homePage = currentPage;
  });

  // Handles browser navigation.
  window.onPopState.listen((event) {
    if (event.state != null) {
      if (event.state != '') {
        changePageWithoutState(pageIndex[event.state]);
      }
    } else {
      changePageWithoutState(homePage);
    }
  });
}