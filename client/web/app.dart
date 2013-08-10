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

import 'dart:async';
import 'dart:html';

import 'package:dartdoc_viewer/data.dart';
import 'package:dartdoc_viewer/item.dart';
import 'package:dartdoc_viewer/read_yaml.dart';
import 'package:dartdoc_viewer/search.dart';
import 'package:web_ui/web_ui.dart';

// TODO(janicejl): YAML path should not be hardcoded. 
// Path to the YAML file being read in. 
const sourcePath = '../../docs/library_list.txt';

/// This is the cut off point between mobile and desktop in pixels. 
// TODO(janicejl): Use pixel desity rather than how many pixels. Look at:
// http://www.mobilexweb.com/blog/ipad-mini-detection-for-html5-user-agent
const int desktopSizeBoundary = 1006;

/// The [Viewer] object being displayed.
Viewer viewer;

/// The Dartdoc Viewer application state.
class Viewer {
  
  @observable bool isDesktop = window.innerWidth > desktopSizeBoundary;
  
  Future finished;

  /// The homepage from which every [Item] can be reached.
  @observable Home homePage;
  
  /// The current page being shown.
  @observable Item currentPage;
  
  /// The current element on the current page being shown (e.g. #dartdoc-top).
  String _hash;

  // Private constructor for singleton instantiation.
  Viewer._() {
    var manifest = retrieveFileContents(sourcePath);
    finished = manifest.then((response) {
      var libraries = response.split('\n');
      currentPage = new Home(libraries);
      homePage = currentPage;
    });
  }
  
  /// The title of the current page.
  String get title => currentPage == null ? '' : currentPage.decoratedName;
  
  /// Creates a list of [Item] objects describing the path to [currentPage].
  List<Item> get breadcrumbs => [homePage]..addAll(currentPage.path);
  
  /// Scrolls the screen to the correct member if necessary.
  void _scrollScreen(String hash, Item destination) {
    if (hash == null) hash = '#dartdoc-top';
    Timer.run(() {
      
      var e = document.query('$hash');
      e.scrollIntoView();
    });
  }
  
  /// Updates [currentPage] to be [page].
  void _updatePage(Item page, String hash) {
    if (page != null) {
      _hash = hash;
      currentPage = page;
      _scrollScreen(hash, page);
    }
  }
  
  /// Loads the [className] class and updates the current page to the
  /// class's member described by [location].
  Future _updateToClassMember(Class clazz, String location, String hash) {
    if (!clazz.isLoaded) {
      return clazz.load().then((_) {
        var destination = pageIndex[location];
        if (destination != null)  {
          _updatePage(destination, hash);
        } else {
          // If the destination is null, then it is a variable in this class.
          var variable = location.split('.').last;
          _updatePage(clazz, '#$variable');
        }
        return true;
      });
    }
    return new Future.value(false);
  }
  
  /// Loads the [libraryName] [Library] and [className] [Class] if necessary
  /// and updates the current page to the member described by [location] 
  /// once the correct member is found and loaded.
  Future _loadAndUpdatePage(String libraryName, String className, 
                           String location, String hash) {
    var destination = pageIndex[location];
    if (destination == null) {
      var library = homePage.itemNamed(libraryName);
      if (library == null) return new Future.value(false);
      if (!library.isLoaded) {
        return library.load().then((_) =>
          _loadAndUpdatePage(libraryName, className, location, hash));
      } else {
        var clazz = pageIndex[className];
        if (clazz != null) {
          return _updateToClassMember(clazz, location, hash);
        } else {
          // The location is of a top-level variable in a library.
          var variable = location.split('.').last;
          _updatePage(library, '#$variable');
          return new Future.value(true);
        }
      }
    } else {
      if (destination is Class && !destination.isLoaded) {
        return destination.load().then((_) {
          _updatePage(destination, hash);
          return true;
        });
      } else {
        _updatePage(destination, hash);
        return new Future.value(true);
      } 
    }
  }
  
  /// Looks for the correct [Item] described by [location]. If it is found,
  /// [currentPage] is updated and state is not pushed to the history api.
  /// Returns a [Future] to determine if a link was found or not.
  /// [location] is a [String] path to the location (either a qualified name
  /// or a url path).
  Future _handleLinkWithoutState(String location) {
    if (location == null || location == '') return new Future.value(false);
    // An extra '/' at the end of the url must be removed.
    if (location.endsWith('/')) 
      location = location.substring(0, location.length - 1);
    if (location == 'home') {
      _updatePage(homePage, null);
      return new Future.value(true);
    }
    // Converts to a qualified name from a url path.
    location = location.replaceAll('/', '.');
    var hashIndex = location.indexOf('#');
    var variableHash;
    var locationWithoutHash = location;
    if (hashIndex != -1) {
      variableHash = location.substring(hashIndex, location.length);
      locationWithoutHash = location.substring(0, hashIndex);
    }
    var members = locationWithoutHash.split('.');
    var libraryName = members.first;
    // Since library names can contain '.' characters, the library part
    // of the input contains '-' characters replacing the '.' characters
    // in the original qualified name to make finding a library easier. These
    // must be changed back to '.' characters to be true qualified names.
    var className = members.length <= 1 ? null :
      '${libraryName.replaceAll('-', '.')}.${members[1]}';
    locationWithoutHash = locationWithoutHash.replaceAll('-', '.');
    return _loadAndUpdatePage(libraryName, className, 
        locationWithoutHash, variableHash);
  }
  
  /// Looks for the correct [Item] described by [location]. If it is found, 
  /// [currentPage] is updated and state is pushed to the history api.
  void handleLink(String location) {
    _handleLinkWithoutState(location).then((response) {
      if (response) _updateState(currentPage);
    });
  }
  
  /// Updates [currentPage] to [page] and pushes state for navigation.
  void changePage(Item page) {
    if (page is LazyItem && !page.isLoaded) {
      page.load().then((_) {
        _updatePage(page, null);
        _updateState(page);
      });
    } else {
      _updatePage(page, null);
      _updateState(page);
    }
  }
  
  /// Pushes state to history for navigation in the browser.
  void _updateState(Item page) {
    String url = '#home';
    for (var member in page.path) {
      url = url == '#home' ? '#${libraryNames[member.name]}' : 
        '$url/${member.name}';
    }
    if (_hash != null) url = '$url$_hash';
    window.history.pushState(url, url.replaceAll('/', '->'), url);
  }
}

/// The latest url reached by a popState event.
String location;

/// Listens for browser navigation and acts accordingly.
void startHistory() {
  window.onPopState.listen((event) {
    location = window.location.hash.replaceFirst('#', '');
    if (viewer.homePage != null) {
      if (location != '') viewer._handleLinkWithoutState(location);
      else viewer._handleLinkWithoutState('home');
    }
  });
}

/// Handles browser navigation.
main() {
  window.onResize.listen((event) {
    viewer.isDesktop = window.innerWidth > desktopSizeBoundary;
  });

  startHistory();
  viewer = new Viewer._();
  // If a user navigates to a page other than the homepage, the viewer
  // must first load fully before navigating to the specified page.
  viewer.finished.then((_) {
    if (location != null && location != '') {
      viewer._handleLinkWithoutState(location);
    }
    retrieveFileContents('../../docs/index.txt').then((String list) {
      var elements = list.split('\n');
      elements.forEach((element) {
        var splitName = element.split(' ');
        index[splitName[0]] = splitName[1];
      });
    });
  });
}