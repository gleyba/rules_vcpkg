#include <QtCore/QtPlugin>
#include <QtWidgets/QApplication>
#include <QtWidgets/QPushButton>

#include <iostream>

Q_IMPORT_PLUGIN(QCocoaIntegrationPlugin);

int main(int argc, char *argv[]) {
    QApplication a(argc, argv);
    QPushButton button ("Hello world!");
    button.show();

    return a.exec(); // .exec starts QApplication and related GUI, this line starts 'event loop'    
}
