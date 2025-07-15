#include <QtWidgets/QApplication>
#include <QtWidgets/QPushButton>

#include <iostream>

int main(int argc, char *argv[]) {
    std::cout << std::getenv("QT_QPA_PLATFORM_PLUGIN_PATH") << std::endl;

    std::system("ls -la ../rules_vcpkg++vcpkg+vcpkg/qt6_plugins/");

    QApplication a(argc, argv);
    QPushButton button ("Hello world!");
    button.show();

    return a.exec(); // .exec starts QApplication and related GUI, this line starts 'event loop'    
}
