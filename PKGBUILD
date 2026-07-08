# Maintainer: Roy Perry <roypery2010@gmail.com>
pkgname=c3nob.c3i
pkgver=1.1.0
pkgrel=1
pkgdesc="A nob.h-like build system but in c3lang"
arch=('any')
url="https://github.com/roypery2010/c3nob.c3i"
license=('Unlicense')
depends=('c3c')
makedepends=('git')

# Tell makepkg to clone the repo directly
source=("git+https://github.com/roypery2010/c3nob.c3i.git#branch=main")
sha256sums=('SKIP')

build() {
    # Cloned repo lives at $srcdir/c3nob.c3i (matches pkgname)
    cd "$srcdir/$pkgname"

    # Compile your project
    c3c compile main.c3 -o c3nob
}

package() {
    cd "$srcdir/$pkgname"

    # Install the compiled binary to your system path
    install -Dm755 c3nob "$pkgdir/usr/bin/c3nob"
}
