"""
Prepares a database made by graphite-web 0.9 for `migrate --fake-initial`.

graphite-web 0.9 created its tables with syncdb, without recording any
migrations. --fake-initial records an app's initial migration as applied
when every table it creates is already there, but graphite-web 1.1's initial
migrations create some tables 0.9 never had, such as dashboard_template, and
so are run instead and fail on the tables that do exist.

For each initial migration that is not recorded but has some of its tables in
the database, the tables it is missing are created as that migration would
create them, leaving every existing table and row as it is.
"""
import os

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "graphite.settings")
django.setup()

from django.db import connection  # noqa: E402
from django.db.migrations.loader import MigrationLoader  # noqa: E402


def models_created_by(migration):
    for operation in migration.operations:
        if operation.__class__.__name__ == "CreateModel":
            yield operation.name_lower


def tables_for(model):
    """the model's table, and the tables of the many-to-many fields it owns"""
    yield model._meta.db_table, model
    for field in model._meta.local_many_to_many:
        through = field.remote_field.through
        if through._meta.auto_created:
            yield through._meta.db_table, through


def main():
    loader = MigrationLoader(connection)
    existing = set(connection.introspection.table_names())

    for key, migration in sorted(loader.disk_migrations.items()):
        if not getattr(migration, "initial", False) or key in loader.applied_migrations:
            continue

        state = loader.project_state(key, at_end=True)
        app_label = key[0]
        tables = []
        for name in models_created_by(migration):
            tables.extend(tables_for(state.apps.get_model(app_label, name)))

        present = [table for table, _ in tables if table in existing]
        missing = [(table, model) for table, model in tables if table not in existing]
        if not present or not missing:
            continue

        with connection.schema_editor() as editor:
            for table, model in missing:
                print("creating {0} for {1}.{2}".format(table, app_label, key[1]))
                if model._meta.auto_created:
                    editor.create_model(model)
                else:
                    # the model's own table alone: its many-to-many tables
                    # are in the list as well, and some may already exist
                    sql, params = editor.table_sql(model)
                    editor.execute(sql, params or None)
                    editor.deferred_sql.extend(editor._model_indexes_sql(model))
                existing.add(table)


if __name__ == "__main__":
    main()
