// Übersetzt src/precomputed_ecmult.c aus libsecp256k1, unverändert (siehe README.md).
// Die Bibliothek enthält statische Hilfen, die nur ihre eigenen Tests
// benutzen, und kürzt Ganzzahlen an Stellen, wo das so gewollt ist; die
// Warnungen dazu (Xcode schaltet -Wshorten-64-to-32 ein) gehören nicht in
// den App-Build. Bitcoin Core baut die Bibliothek ebenso ohne sie.
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#include "src/precomputed_ecmult.c"
