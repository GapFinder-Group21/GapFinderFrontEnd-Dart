// The tables of one feature. Every teammate describes the tables of their feature in a module
// and adds it to databaseModules, so nobody edits the core of the database.
class DatabaseModule {
  final String name;
  // SQL statements that create the tables and indexes. They must use IF NOT EXISTS.
  final List<String> createStatements;

  const DatabaseModule({required this.name, required this.createStatements});
}
