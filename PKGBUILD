pkgname=c3nob
pkgver=1.0.0
pkgrel=1
pkgdesc="A nob.h style build system implementation for the C3 programming language"
arch=('any')
url="https://github.com/roypery2010/c3nob.c3i"
license=('MIT')
depends=('c3c')

# Arch downloads your source from your GitHub link here:
source=("${pkgname}-${pkgver}.tar.gz::https://github.com/roypery2010/c3nob.c3i/archive/refs/tags/v${pkgver}.tar.gz")
sha256sums=('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILx5VuZY36SjNNRc9Q+4m6binOKUodIBMuAtWO/Hrnes roypery2010@gmail.com') 

package() {
    cd "${srcdir}/${pkgname}.c3i-${pkgver}"
    install -Dm644 c3nob.c3i "${pkgdir}/usr/share/c3/c3nob.c3i"
}