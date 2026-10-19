import 'package:gapfinderfrontend_dart/core/storage/database_module.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_database_module.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_database_module.dart';

// Cada integrante agrega aquí su módulo en una línea
final List<DatabaseModule> databaseModules = [
  outboxModule,
  sofiaDatabaseModule,
  joelDatabaseModule,
];
