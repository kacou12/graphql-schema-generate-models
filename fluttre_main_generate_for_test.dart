import "package:gql/language.dart" as lang;
import "package:gql/schema.dart" as gql_schema;

import 'package:flutter/services.dart' show rootBundle;

generate() async {
  // final Directory directory = await getApplicationDocumentsDirectory();

  final Directory? directory = await getExternalStorageDirectory();

  String appDocumentsPath = directory!.path;

  final namePackage = appDocumentsPath
      .split('/')[appDocumentsPath.split('/').length - 2]
      .split('.')
      .last;

  String schemaContent = await rootBundle.loadString('lib/schema.graphql');

  //Because ID is not au Dart Type
  schemaContent = schemaContent.replaceAll("ID", 'String');

  final schemaFile = File('$appDocumentsPath/schema.graphql');

  schemaFile.writeAsStringSync(schemaContent);

  final outputDirectory = Directory(appDocumentsPath);

  final schemaContents = schemaFile.readAsStringSync();

  final schema = gql_schema.GraphQLSchema.fromNode(
    lang.parseString(
      schemaContents,
      url: schemaFile.path,
    ),
  );

  final enums = generateEnums(schema);

  final models = generateModels(schema, namePackage, enums);

  models.forEach((className, modelContent) async {
    final modelFile = File(
        '${outputDirectory.path}/${formatNameTypeForImport(className)}.dart');
    await modelFile.create();
    modelFile.writeAsStringSync(modelContent);
  });

  print('Génération des fichiers de modèle terminée !');
}

Map<String, String> generateModels(gql_schema.GraphQLSchema schema,
    String namePackage, Map<String, String> enums) {
  final models = <String, String>{};

  for (final type in schema.typeMap.values) {
    if (type is gql_schema.ObjectTypeDefinition) {
      final className = type.name;
      final modelContent = generateModel(type, namePackage, enums);
      models[className!] = modelContent;
    }
  }

  return models;
}

String generateModel(gql_schema.ObjectTypeDefinition type, String namePackage,
    Map<String, String> enums) {
  final className = type.name;
  final buffer = StringBuffer();

  // setHeader(type.fields, namePackage);

  buffer.writeln(setHeader(type.fields, namePackage, className!, enums));

  buffer.writeln('class $className {');

  for (final field in type.fields) {
    final fieldName = field.name;

    final fieldType = getTypeName(field.type!);

    if (fieldName == "_id") {
      buffer.writeln("  @JsonKey(name: '_id')");
      buffer.writeln('  final $fieldType id;');
    } else {
      buffer.writeln('  final $fieldType $fieldName;');
    }
  }

  buffer.writeln();

  buffer.writeln('  $className({');
  for (final field in type.fields) {
    final fieldName = field.name;

    if (field.type!.toString().contains("!")) {
      if (fieldName == "_id") {
        buffer.writeln('    required this.id,');
      } else {
        buffer.writeln('    required this.$fieldName,');
      }
    } else {
      buffer.writeln('    this.$fieldName,');
    }
  }
  buffer.writeln('  });');

  buffer.writeln(setBottom(className));

  buffer.writeln('}');

  return buffer.toString();
}

String getTypeName(gql_schema.GraphQLType type) {
  final requiredCaract = type.toString().contains("!") ? "" : "?";
  final String baseTypeName = formatIntBoolToDartType(type.baseTypeName);

  if (type is List) {
    return 'List<$baseTypeName>$requiredCaract';
  }
  return '$baseTypeName$requiredCaract';
}

//Set import line fro non scalar type
String setHeader(List<gql_schema.FieldDefinition> fields, String namePackage,
    String className, Map<String, String> enums) {
  String? addToBuffer;

  final scalars = ['int', 'double', 'String', 'bool', 'DateTime'];
  final enumsName = enums.entries
      .map((MapEntry<String, String> mapEntry) => mapEntry.key)
      .toList();

  for (final field in fields) {
    bool isScalarOrEnum = false;

    // final fieldType = getTypeName(field.type!);
    final fieldType =
        formatIntBoolToDartType(field.type!.baseTypeName.replaceFirst("!", ''));
    // is enum
    if (enumsName.contains(fieldType)) {
      isScalarOrEnum = true;
    }

    // is scalar
    for (String scalar in scalars) {
      // if (fieldType.contains(scalar)) {
      if (fieldType == scalar) {
        isScalarOrEnum = true;
        break;
      }
    }

    final nameCamelCaseForImport =
        formatNameTypeForImport(field.type!.baseTypeName);

    if (!isScalarOrEnum && addToBuffer != null) {
      addToBuffer =
          "$addToBuffer \nimport 'package:$namePackage/generated/$nameCamelCaseForImport.dart';\n";
    } else if (!isScalarOrEnum) {
      addToBuffer =
          "\nimport 'package:$namePackage/generated/$nameCamelCaseForImport.dart';\n";
    }
  }

  //if has some import
  if (addToBuffer != null) {
    addToBuffer =
        "$addToBuffer \nimport 'package:json_annotation/json_annotation.dart';\n";
  }
  //if has no import
  else {
    addToBuffer = "import 'package:json_annotation/json_annotation.dart';\n";
  }

  addToBuffer =
      "$addToBuffer \npart '${formatNameTypeForImport(className)}.g.dart';\n";

  for (final field in fields) {
    // final fieldType = getTypeName(field.type!);
    final fieldType =
        formatIntBoolToDartType(field.type!.baseTypeName.replaceFirst("!", ''));
    if (enumsName.contains(fieldType)) {
      addToBuffer =
          "$addToBuffer \n${formatEnum(fieldType, enums[fieldType]!)}\n";
    }
  }

  addToBuffer = "$addToBuffer \n@JsonSerializable()\n";

  return addToBuffer;
}

//Set factory and other
String setBottom(String className) {
  return '''\n  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);

  Map<String, dynamic> toJson() => _\$${className}ToJson(this);
  ''';
}

String formatNameTypeForImport(String nameType) {
// String text = 'camelCase';
  final exp = RegExp('(?<=[a-z])[A-Z]');
  String result =
      nameType.replaceAllMapped(exp, (m) => '_${m.group(0)}').toLowerCase();
  return result;
}

String formatIntBoolToDartType(String typeName) {
  if (typeName == "Boolean") {
    return "bool";
  }
  if (typeName == "Int") {
    return "int";
  }
  if (typeName == "Float") {
    return "double";
  }
  return typeName;
}

/// ************  Enum Generating   *******************
Map<String, String> generateEnums(gql_schema.GraphQLSchema schema) {
  final enums = <String, String>{};

  for (final type in schema.typeMap.values) {
    if (type is gql_schema.EnumTypeDefinition) {
      final className = type.name;
      // final modelContent = generateModel(type, namePackage);
      final modelContent = type.values.toString();
      enums[className!] = modelContent;
    }
  }

  return enums;
}

String formatEnum(String name, String values) {
  values = values.replaceAll('[', '{').replaceAll(']', '}');
  return "enum $name $values";
}
