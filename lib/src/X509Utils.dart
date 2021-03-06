import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:basic_utils/src/model/x509/X509CertificateData.dart';
import 'package:basic_utils/src/model/x509/X509CertificatePublicKeyData.dart';
import 'package:basic_utils/src/model/x509/X509CertificateValidity.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/pointycastle.dart';

import '../basic_utils.dart';

///
/// Helper class for certificate operations.
///
class X509Utils {
  static final String BEGIN_PRIVATE_KEY = '-----BEGIN PRIVATE KEY-----';
  static final String END_PRIVATE_KEY = '-----END PRIVATE KEY-----';

  static final String BEGIN_PUBLIC_KEY = '-----BEGIN PUBLIC KEY-----';
  static final String END_PUBLIC_KEY = '-----END PUBLIC KEY-----';

  static final String BEGIN_CSR = '-----BEGIN CERTIFICATE REQUEST-----';
  static final String END_CSR = '-----END CERTIFICATE REQUEST-----';

  static final String BEGIN_EC_PRIVATE_KEY = '-----BEGIN EC PRIVATE KEY-----';
  static final String END_EC_PRIVATE_KEY = '-----END EC PRIVATE KEY-----';

  static final String BEGIN_EC_PUBLIC_KEY = '-----BEGIN EC PUBLIC KEY-----';
  static final String END_EC_PUBLIC_KEY = '-----END EC PUBLIC KEY-----';

  static final Map<String, String> DN = {
    'cn': '2.5.4.3',
    'sn': '2.5.4.4',
    'c': '2.5.4.6',
    'l': '2.5.4.7',
    'st': '2.5.4.8',
    's': '2.5.4.8',
    'o': '2.5.4.10',
    'ou': '2.5.4.11',
    'title': '2.5.4.12',
    'registeredAddress': '2.5.4.26',
    'member': '2.5.4.31',
    'owner': '2.5.4.32',
    'roleOccupant': '2.5.4.33',
    'seeAlso': '2.5.4.34',
    'givenName': '2.5.4.42',
    'initials': '2.5.4.43',
    'generationQualifier': '2.5.4.44',
    'dmdName': '2.5.4.54',
    'alias': '2.5.6.1',
    'country': '2.5.6.2',
    'locality': '2.5.6.3',
    'organization': '2.5.6.4',
    'organizationalUnit': '2.5.6.5',
    'person': '2.5.6.6',
    'organizationalPerson': '2.5.6.7',
    'organizationalRole': '2.5.6.8',
    'groupOfNames': '2.5.6.9',
    'residentialPerson': '2.5.6.10',
    'applicationProcess': '2.5.6.11',
    'applicationEntity': '2.5.6.12',
    'dSA': '2.5.6.13',
    'device': '2.5.6.14',
    'strongAuthenticationUser': '2.5.6.15',
    'certificationAuthority': '2.5.6.16',
    'groupOfUniqueNames': '2.5.6.17',
    'userSecurityInformation': '2.5.6.18',
    'certificationAuthority-V2': '2.5.6.16.2',
    'cRLDistributionPoint': '2.5.6.19',
    'dmd': '2.5.6.20',
    'md5WithRSAEncryption': '1.2.840.113549.1.1.4',
    'rsaEncryption': '1.2.840.113549.1.1.1',
    'organizationalUnitName': '2.5.4.11',
    'organizationName': '2.5.4.10',
    'stateOrProvinceName': '2.5.4.8',
    'commonName': '2.5.4.3',
    'surname': '2.5.4.4',
    'countryName': '2.5.4.6',
    'localityName': '2.5.4.7',
    'streetAddress': '2.5.4.9'
  };

  ///
  /// Generates a [AsymmetricKeyPair] with the given [keySize].
  ///
  static AsymmetricKeyPair generateKeyPair({int keySize = 2048}) {
    var keyParams =
        RSAKeyGeneratorParameters(BigInt.parse('65537'), keySize, 12);

    var secureRandom = FortunaRandom();
    var random = Random.secure();
    var seeds = <int>[];
    for (var i = 0; i < 32; i++) {
      seeds.add(random.nextInt(255));
    }
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    var rngParams = ParametersWithRandom(keyParams, secureRandom);
    var k = RSAKeyGenerator();
    k.init(rngParams);

    return k.generateKeyPair();
  }

  ///
  /// Generates a elliptic curve [AsymmetricKeyPair] with the **prime256v1** algorithm.
  ///
  static AsymmetricKeyPair generateEcKeyPair() {
    var keyParams = ECKeyGeneratorParameters(ECCurve_prime256v1());

    var secureRandom = _getSecureRandom();

    var rngParams = ParametersWithRandom(keyParams, secureRandom);
    var k = ECKeyGenerator();
    k.init(rngParams);

    return k.generateKeyPair();
  }

  ///
  /// Formats the given [key] by chunking the [key] and adding the [begin] and [end] to the [key].
  ///
  /// The line length will be defined by the given [chunkSize]. The default value is 64.
  ///
  /// Each line will be delimited by the given [lineDelimiter]. The default value is '\n'.w
  ///
  static String formatKeyString(String key, String begin, String end,
      {int chunkSize = 64, String lineDelimiter = '\n'}) {
    var sb = StringBuffer();
    var chunks = StringUtils.chunk(key, chunkSize);
    sb.write(begin + lineDelimiter);
    for (var s in chunks) {
      sb.write(s + lineDelimiter);
    }
    sb.write(end);
    return sb.toString();
  }

  ///
  /// Generates a Certificate Signing Request with the given [attributes] using the given [privateKey] and [publicKey].
  ///
  static String generateRsaCsrPem(Map<String, String> attributes,
      RSAPrivateKey privateKey, RSAPublicKey publicKey) {
    var encodedDN = encodeDN(attributes);

    var blockDN = ASN1Sequence();
    blockDN.add(ASN1Integer(BigInt.from(0)));
    blockDN.add(encodedDN);
    blockDN.add(_makePublicKeyBlock(publicKey));
    blockDN.add(ASN1Null(tag: 0xA0)); // let's call this WTF

    var blockProtocol = ASN1Sequence();
    blockProtocol.add(ASN1ObjectIdentifier.fromName('sha256WithRSAEncryption'));
    blockProtocol.add(ASN1Null());

    var outer = ASN1Sequence();
    outer.add(blockDN);
    outer.add(blockProtocol);
    outer.add(ASN1BitString(_rsaSign(blockDN.encodedBytes, privateKey)));
    var chunks = StringUtils.chunk(base64.encode(outer.encodedBytes), 64);
    return '$BEGIN_CSR\n${chunks.join('\r\n')}\n$END_CSR';
  }

  static Uint8List _rsaSign(Uint8List inBytes, RSAPrivateKey privateKey) {
    var signer = Signer('SHA-256/RSA');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

    RSASignature signature = signer.generateSignature(inBytes);

    return signature.bytes;
  }

  ///
  /// Generates a eliptic curve Certificate Signing Request with the given [attributes] using the given [privateKey] and [publicKey].
  ///
  /// The CSR will be signed with algorithm **SHA-256/ECDSA**.
  ///
  static String generateEccCsrPem(Map<String, String> attributes,
      ECPrivateKey privateKey, ECPublicKey publicKey) {
    ASN1ObjectIdentifier.registerFrequentNames();
    var encodedDN = encodeDN(attributes);
    var publicKeySequence = _makeEccPublicKeyBlock(publicKey);

    var blockDN = ASN1Sequence();
    blockDN.add(ASN1Integer(BigInt.from(0)));
    blockDN.add(encodedDN);
    blockDN.add(publicKeySequence);
    blockDN.add(ASN1Null(tag: 0xA0)); // let's call this WTF

    var blockSignatureAlgorithm = ASN1Sequence();
    blockSignatureAlgorithm
        .add(ASN1ObjectIdentifier.fromName('ecdsaWithSHA256'));

    var ecSignature = eccSign(blockDN.encodedBytes, privateKey);

    var bitStringSequence = ASN1Sequence();
    bitStringSequence.add(ASN1Integer(ecSignature.r));
    bitStringSequence.add(ASN1Integer(ecSignature.s));
    var blockSignatureValue = ASN1BitString(bitStringSequence.encodedBytes);

    var outer = ASN1Sequence();
    outer.add(blockDN);
    outer.add(blockSignatureAlgorithm);
    outer.add(blockSignatureValue);
    var chunks = StringUtils.chunk(base64.encode(outer.encodedBytes), 64);
    return '$BEGIN_CSR\n${chunks.join('\r\n')}\n$END_CSR';
  }

  static ECSignature eccSign(Uint8List inBytes, ECPrivateKey privateKey) {
    var signer = Signer('SHA-256/ECDSA');
    //var signer = ECDSASigner();
    var privParams = PrivateKeyParameter<ECPrivateKey>(privateKey);
    var signParams = ParametersWithRandom(
      privParams,
      _getSecureRandom(),
    );
    signer.init(true, signParams);

    return signer.generateSignature(inBytes);
  }

  static SecureRandom _getSecureRandom() {
    var secureRandom = FortunaRandom();
    var random = Random.secure();
    var seeds = <int>[];
    for (var i = 0; i < 32; i++) {
      seeds.add(random.nextInt(255));
    }
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  ///
  /// Encode the given [asn1Object] to PEM format and adding the [begin] and [end].
  ///
  static String encodeASN1ObjectToPem(
      ASN1Object asn1Object, String begin, String end) {
    var chunks = StringUtils.chunk(base64.encode(asn1Object.encodedBytes), 64);
    return '$begin\n${chunks.join('\r\n')}\n$end';
  }

  ///
  /// Enode the given [publicKey] to PEM format.
  ///
  static String encodeRSAPublicKeyToPem(RSAPublicKey publicKey) {
    var algorithmSeq = ASN1Sequence();
    var algorithmAsn1Obj = ASN1Object.fromBytes(Uint8List.fromList(
        [0x6, 0x9, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0xd, 0x1, 0x1, 0x1]));
    var paramsAsn1Obj = ASN1Object.fromBytes(Uint8List.fromList([0x5, 0x0]));
    algorithmSeq.add(algorithmAsn1Obj);
    algorithmSeq.add(paramsAsn1Obj);

    var publicKeySeq = ASN1Sequence();
    publicKeySeq.add(ASN1Integer(publicKey.modulus));
    publicKeySeq.add(ASN1Integer(publicKey.exponent));
    var publicKeySeqBitString =
        ASN1BitString(Uint8List.fromList(publicKeySeq.encodedBytes));

    var topLevelSeq = ASN1Sequence();
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqBitString);
    var dataBase64 = base64.encode(topLevelSeq.encodedBytes);
    var chunks = StringUtils.chunk(dataBase64, 64);

    return '$BEGIN_PUBLIC_KEY\n${chunks.join('\n')}\n$END_PUBLIC_KEY';
  }

  ///
  /// Enode the given elliptic curve [publicKey] to PEM format.
  ///
  /// This is descripted in https://tools.ietf.org/html/rfc5480
  ///
  /// ```ASN1
  /// SubjectPublicKeyInfo  ::=  SEQUENCE  {
  ///     algorithm         AlgorithmIdentifier,
  ///     subjectPublicKey  BIT STRING
  /// }
  /// ```
  ///
  static String encodeEcPublicKeyToPem(ECPublicKey publicKey) {
    ASN1ObjectIdentifier.registerFrequentNames();
    var outer = ASN1Sequence();
    var algorithm = ASN1Sequence();
    algorithm.add(ASN1ObjectIdentifier.fromName('ecPublicKey'));
    algorithm.add(ASN1ObjectIdentifier.fromName('prime256v1'));
    var subjectPublicKey = ASN1BitString(publicKey.Q.getEncoded(false));

    outer.add(algorithm);
    outer.add(subjectPublicKey);
    var dataBase64 = base64.encode(outer.encodedBytes);
    var chunks = StringUtils.chunk(dataBase64, 64);

    return '$BEGIN_EC_PUBLIC_KEY\n${chunks.join('\n')}\n$END_EC_PUBLIC_KEY';
  }

  ///
  /// Enode the given elliptic curve [publicKey] to PEM format.
  ///
  /// This is descripted in https://tools.ietf.org/html/rfc5915
  ///
  /// ```ASN1
  /// ECPrivateKey ::= SEQUENCE {
  ///   version        INTEGER { ecPrivkeyVer1(1) } (ecPrivkeyVer1),
  ///   privateKey     OCTET STRING
  ///   parameters [0] ECParameters {{ NamedCurve }} OPTIONAL
  ///   publicKey  [1] BIT STRING OPTIONAL
  /// }
  ///
  /// ```
  ///
  /// As descripted in the mentioned RFC, all optional values will always be set.
  ///
  static String encodeEcPrivateKeyToPem(ECPrivateKey ecPrivateKey) {
    ASN1ObjectIdentifier.registerFrequentNames();
    var outer = ASN1Sequence();

    var version = ASN1Integer(BigInt.from(1));
    var privateKeyAsBytes = _bigIntToBytes(ecPrivateKey.d);
    var privateKey = ASN1OctetString(privateKeyAsBytes);
    var choice = ASN1Sequence(tag: 0xA0);

    choice
        .add(ASN1ObjectIdentifier.fromName(ecPrivateKey.parameters.domainName));

    var publicKey = ASN1Sequence(tag: 0xA1);

    var subjectPublicKey =
        ASN1BitString(ecPrivateKey.parameters.G.getEncoded(false));
    publicKey.add(subjectPublicKey);

    outer.add(version);
    outer.add(privateKey);
    outer.add(choice);
    outer.add(publicKey);
    var dataBase64 = base64.encode(outer.encodedBytes);
    var chunks = StringUtils.chunk(dataBase64, 64);

    return '$BEGIN_EC_PRIVATE_KEY\n${chunks.join('\n')}\n$END_EC_PRIVATE_KEY';
  }

  ///
  /// Enode the given [rsaPrivateKey] to PEM format.
  ///
  static String encodeRSAPrivateKeyToPem(RSAPrivateKey rsaPrivateKey) {
    var version = ASN1Integer(BigInt.from(0));

    var algorithmSeq = ASN1Sequence();
    var algorithmAsn1Obj = ASN1Object.fromBytes(Uint8List.fromList(
        [0x6, 0x9, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0xd, 0x1, 0x1, 0x1]));
    var paramsAsn1Obj = ASN1Object.fromBytes(Uint8List.fromList([0x5, 0x0]));
    algorithmSeq.add(algorithmAsn1Obj);
    algorithmSeq.add(paramsAsn1Obj);

    var privateKeySeq = ASN1Sequence();
    var modulus = ASN1Integer(rsaPrivateKey.n);
    var publicExponent = ASN1Integer(BigInt.parse('65537'));
    var privateExponent = ASN1Integer(rsaPrivateKey.d);
    var p = ASN1Integer(rsaPrivateKey.p);
    var q = ASN1Integer(rsaPrivateKey.q);
    var dP = rsaPrivateKey.d % (rsaPrivateKey.p - BigInt.from(1));
    var exp1 = ASN1Integer(dP);
    var dQ = rsaPrivateKey.d % (rsaPrivateKey.q - BigInt.from(1));
    var exp2 = ASN1Integer(dQ);
    var iQ = rsaPrivateKey.q.modInverse(rsaPrivateKey.p);
    var co = ASN1Integer(iQ);

    privateKeySeq.add(version);
    privateKeySeq.add(modulus);
    privateKeySeq.add(publicExponent);
    privateKeySeq.add(privateExponent);
    privateKeySeq.add(p);
    privateKeySeq.add(q);
    privateKeySeq.add(exp1);
    privateKeySeq.add(exp2);
    privateKeySeq.add(co);
    var publicKeySeqOctetString =
        ASN1OctetString(Uint8List.fromList(privateKeySeq.encodedBytes));

    var topLevelSeq = ASN1Sequence();
    topLevelSeq.add(version);
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqOctetString);
    var dataBase64 = base64.encode(topLevelSeq.encodedBytes);
    var chunks = StringUtils.chunk(dataBase64, 64);
    return '$BEGIN_PRIVATE_KEY\n${chunks.join('\n')}\n$END_PRIVATE_KEY';
  }

  ///
  /// Decode a [RSAPrivateKey] from the given [pem] String.
  ///
  static RSAPrivateKey privateKeyFromPem(String pem) {
    if (pem == null) {
      throw ArgumentError('Argument must not be null.');
    }
    var bytes = getBytesFromPEMString(pem);
    return privateKeyFromDERBytes(bytes);
  }

  ///
  /// Decode a [RSAPublicKey] from the given [pem] String.
  ///
  static RSAPublicKey publicKeyFromPem(String pem) {
    if (pem == null) {
      throw ArgumentError('Argument must not be null.');
    }
    var bytes = getBytesFromPEMString(pem);
    var asn1Parser = ASN1Parser(bytes);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    var publicKeyBitString = topLevelSeq.elements[1];

    var publicKeyAsn = ASN1Parser(publicKeyBitString.contentBytes());
    ASN1Sequence publicKeySeq = publicKeyAsn.nextObject();
    var modulus = publicKeySeq.elements[0] as ASN1Integer;
    var exponent = publicKeySeq.elements[1] as ASN1Integer;

    var rsaPublicKey =
        RSAPublicKey(modulus.valueAsBigInteger, exponent.valueAsBigInteger);

    return rsaPublicKey;
  }

  ///
  /// Parses the given PEM to a [X509CertificateData] object.
  ///
  /// Throws an [ASN1Exception] if the pem could not be read by the [ASN1Parser].
  ///
  static X509CertificateData x509CertificateFromPem(String pem) {
    if (pem == null) {
      throw ArgumentError('Argument must not be null.');
    }
    ASN1ObjectIdentifier.registerFrequentNames();
    var bytes = getBytesFromPEMString(pem);
    var asn1Parser = ASN1Parser(bytes);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    var dataSequence = topLevelSeq.elements.elementAt(0) as ASN1Sequence;
    var version;
    var element = 0;
    var serialInteger;
    if (dataSequence.elements.elementAt(0) is ASN1Integer) {
      // The version ASN1Object ist missing use version
      version = 1;
      // Serialnumber
      serialInteger = dataSequence.elements.elementAt(element) as ASN1Integer;
      element = -1;
    } else {
      // Version
      var versionObject = dataSequence.elements.elementAt(element + 0);
      version = versionObject.valueBytes().elementAt(2);
      // Serialnumber
      serialInteger =
          dataSequence.elements.elementAt(element + 1) as ASN1Integer;
    }
    var serialNumber = serialInteger.valueAsBigInteger;

    // Signature
    var signatureSequence =
        dataSequence.elements.elementAt(element + 2) as ASN1Sequence;
    var o = signatureSequence.elements.elementAt(0) as ASN1ObjectIdentifier;
    var signatureAlgorithm = o.identifier;

    // Issuer
    var issuerSequence =
        dataSequence.elements.elementAt(element + 3) as ASN1Sequence;
    var issuer = <String, String>{};
    for (ASN1Set s in issuerSequence.elements) {
      var setSequence = s.elements.elementAt(0) as ASN1Sequence;
      var o = setSequence.elements.elementAt(0) as ASN1ObjectIdentifier;
      var object = setSequence.elements.elementAt(1);
      var value = '';
      if (object is ASN1UTF8String) {
        var objectAsUtf8 = object;
        value = objectAsUtf8.utf8StringValue;
      } else if (object is ASN1PrintableString) {
        var objectPrintable = object;
        value = objectPrintable.stringValue;
      } else if (object is ASN1TeletextString) {
        var objectTeletext = object;
        value = objectTeletext.stringValue;
      }
      issuer.putIfAbsent(o.identifier, () => value);
    }

    // Validity
    var validitySequence =
        dataSequence.elements.elementAt(element + 4) as ASN1Sequence;
    var asn1FromDateTime;
    var asn1ToDateTime;
    if (validitySequence.elements.elementAt(0) is ASN1UtcTime) {
      var asn1From = validitySequence.elements.elementAt(0) as ASN1UtcTime;
      asn1FromDateTime = asn1From.dateTimeValue;
    } else {
      var asn1From =
          validitySequence.elements.elementAt(0) as ASN1GeneralizedTime;
      asn1FromDateTime = asn1From.dateTimeValue;
    }
    if (validitySequence.elements.elementAt(1) is ASN1UtcTime) {
      var asn1To = validitySequence.elements.elementAt(1) as ASN1UtcTime;
      asn1ToDateTime = asn1To.dateTimeValue;
    } else {
      var asn1To =
          validitySequence.elements.elementAt(1) as ASN1GeneralizedTime;
      asn1ToDateTime = asn1To.dateTimeValue;
    }

    var validity = X509CertificateValidity(
        notBefore: asn1FromDateTime, notAfter: asn1ToDateTime);

    // Subject
    var subjectSequence =
        dataSequence.elements.elementAt(element + 5) as ASN1Sequence;
    var subject = <String, String>{};
    for (ASN1Set s in subjectSequence.elements) {
      var setSequence = s.elements.elementAt(0) as ASN1Sequence;
      var o = setSequence.elements.elementAt(0) as ASN1ObjectIdentifier;
      var object = setSequence.elements.elementAt(1);
      var value = '';
      if (object is ASN1UTF8String) {
        var objectAsUtf8 = object;
        value = objectAsUtf8.utf8StringValue;
      } else if (object is ASN1PrintableString) {
        var objectPrintable = object;
        value = objectPrintable.stringValue;
      }
      var identifier = o.identifier ?? 'unknown';
      subject.putIfAbsent(identifier, () => value);
    }

    // Public Key
    var pubKeySequence =
        dataSequence.elements.elementAt(element + 6) as ASN1Sequence;

    var algoSequence = pubKeySequence.elements.elementAt(0) as ASN1Sequence;
    var pubKeyOid = algoSequence.elements.elementAt(0) as ASN1ObjectIdentifier;

    var pubKey = pubKeySequence.elements.elementAt(1) as ASN1BitString;
    var asn1PubKeyParser = ASN1Parser(pubKey.contentBytes());
    var next;
    try {
      next = asn1PubKeyParser.nextObject();
    } catch (RangeError) {
      // continue
    }
    var pubKeyLength = 0;

    Uint8List pubKeyAsBytes;

    if (next != null && next is ASN1Sequence) {
      var s = next;
      var key = s.elements.elementAt(0) as ASN1Integer;
      pubKeyLength = key.valueAsBigInteger.bitLength;
      pubKeyAsBytes = s.encodedBytes;
    } else {
      pubKeyAsBytes = pubKey.contentBytes();
      pubKeyLength = pubKey.contentBytes().length * 8;
    }
    var pubKeyThumbprint =
        CryptoUtils.getSha1ThumbprintFromBytes(pubKeySequence.encodedBytes);
    var pubKeySha256Thumbprint =
        CryptoUtils.getSha256ThumbprintFromBytes(pubKeySequence.encodedBytes);
    var publicKeyData = X509CertificatePublicKeyData(
        algorithm: pubKeyOid.identifier,
        bytes: _bytesAsString(pubKeyAsBytes),
        length: pubKeyLength,
        sha1Thumbprint: pubKeyThumbprint,
        sha256Thumbprint: pubKeySha256Thumbprint);

    var sha1String = CryptoUtils.getSha1ThumbprintFromBytes(bytes);
    var md5String = CryptoUtils.getMd5ThumbprintFromBytes(bytes);
    var sha256String = CryptoUtils.getSha256ThumbprintFromBytes(bytes);
    List<String> sans;
    if (version > 1) {
      // Extensions
      var extensionObject = dataSequence.elements.elementAt(element + 7);
      var extParser = ASN1Parser(extensionObject.valueBytes());
      var extSequence = extParser.nextObject() as ASN1Sequence;

      extSequence.elements.forEach((ASN1Object subseq) {
        var seq = subseq as ASN1Sequence;
        var oi = seq.elements.elementAt(0) as ASN1ObjectIdentifier;
        if (oi.identifier == '2.5.29.17') {
          sans = _fetchSansFromExtension(seq.elements.elementAt(1));
        }
      });
    }

    return X509CertificateData(
        version: version,
        serialNumber: serialNumber,
        signatureAlgorithm: signatureAlgorithm,
        issuer: issuer,
        validity: validity,
        subject: subject,
        sha1Thumbprint: sha1String,
        sha256Thumbprint: sha256String,
        md5Thumbprint: md5String,
        publicKeyData: publicKeyData,
        subjectAlternativNames: sans);
  }

  ///
  /// Helper function for decoding the base64 in [pem].
  ///
  /// Throws an ArgumentError if the given [pem] is not sourounded by begin marker -----BEGIN and
  /// endmarker -----END or the [pem] consists of less than two lines.
  ///
  static Uint8List getBytesFromPEMString(String pem) {
    var lines = LineSplitter.split(pem)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.length < 2 ||
        !lines.first.startsWith('-----BEGIN') ||
        !lines.last.startsWith('-----END')) {
      throw ArgumentError('The given string does not have the correct '
          'begin/end markers expected in a PEM file.');
    }
    var base64 = lines.sublist(1, lines.length - 1).join('');
    return Uint8List.fromList(base64Decode(base64));
  }

  ///
  /// Decode the given [bytes] into an [RSAPrivateKey].
  ///
  static RSAPrivateKey privateKeyFromDERBytes(Uint8List bytes) {
    var asn1Parser = ASN1Parser(bytes);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    //ASN1Object version = topLevelSeq.elements[0];
    //ASN1Object algorithm = topLevelSeq.elements[1];
    var privateKey = topLevelSeq.elements[2];

    asn1Parser = ASN1Parser(privateKey.contentBytes());
    var pkSeq = asn1Parser.nextObject() as ASN1Sequence;

    var modulus = pkSeq.elements[1] as ASN1Integer;
    //ASN1Integer publicExponent = pkSeq.elements[2] as ASN1Integer;
    var privateExponent = pkSeq.elements[3] as ASN1Integer;
    var p = pkSeq.elements[4] as ASN1Integer;
    var q = pkSeq.elements[5] as ASN1Integer;
    //ASN1Integer exp1 = pkSeq.elements[6] as ASN1Integer;
    //ASN1Integer exp2 = pkSeq.elements[7] as ASN1Integer;
    //ASN1Integer co = pkSeq.elements[8] as ASN1Integer;

    var rsaPrivateKey = RSAPrivateKey(
        modulus.valueAsBigInteger,
        privateExponent.valueAsBigInteger,
        p.valueAsBigInteger,
        q.valueAsBigInteger);

    return rsaPrivateKey;
  }

  ///
  /// Decode the given [asnSequence] into an [RSAPrivateKey].
  ///
  static RSAPrivateKey privateKeyFromASN1Sequence(ASN1Sequence asnSequence) {
    var objects = asnSequence.elements;

    var asnIntegers = objects.take(9).map((o) => o as ASN1Integer).toList();

    var version = asnIntegers.first;
    if (version.valueAsBigInteger != BigInt.zero) {
      throw ArgumentError(
          'Expected version 0, got: ${version.valueAsBigInteger}.');
    }

    var key = RSAPrivateKey(
        asnIntegers[1].valueAsBigInteger,
        asnIntegers[2].valueAsBigInteger,
        asnIntegers[3].valueAsBigInteger,
        asnIntegers[4].valueAsBigInteger);

    var bitLength = key.n.bitLength;
    if (bitLength != 1024 && bitLength != 2048 && bitLength != 4096) {
      throw ArgumentError('The RSA modulus has a bit length of $bitLength. '
          'Only 1024, 2048 and 4096 are supported.');
    }
    return key;
  }

  static Uint8List _bigIntToBytes(BigInt n) {
    var bytes = (n.bitLength + 7) >> 3;

    var b256 = BigInt.from(256);
    var result = Uint8List(bytes);

    for (var i = 0; i < bytes; i++) {
      result[i] = n.remainder(b256).toInt();
      n = n >> 8;
    }

    return result;
  }

  ///
  /// Converts the [RSAPublicKey.modulus] from the given [publicKey] to a [Uint8List].
  ///
  static Uint8List rsaPublicKeyModulusToBytes(RSAPublicKey publicKey) =>
      _bigIntToBytes(publicKey.modulus);

  ///
  /// Converts the [RSAPublicKey.exponent] from the given [publicKey] to a [Uint8List].
  ///
  static Uint8List rsaPublicKeyExponentToBytes(RSAPublicKey publicKey) =>
      _bigIntToBytes(publicKey.exponent);

  ///
  /// Converts the [RSAPrivateKey.modulus] from the given [privateKey] to a [Uint8List].
  ///
  static Uint8List rsaPrivateKeyModulusToBytes(RSAPrivateKey privateKey) =>
      _bigIntToBytes(privateKey.modulus);

  ///
  /// Encode the given [dn] (Distinguished Name) to a [ASN1Object].
  ///
  /// For supported DN see the rf at <https://tools.ietf.org/html/rfc2256>
  ///
  static ASN1Object encodeDN(Map<String, String> dn) {
    var distinguishedName = ASN1Sequence();
    ASN1ObjectIdentifier.registerFrequentNames();
    dn.forEach((name, value) {
      var oid = ASN1ObjectIdentifier.fromName(name);
      if (oid == null) {
        throw ArgumentError('Unknown distinguished name field $name');
      }

      ASN1Object ovalue;
      switch (name.toUpperCase()) {
        case 'C':
          ovalue = ASN1PrintableString(value);
          break;
        case 'CN':
        case 'O':
        case 'L':
        case 'S':
        default:
          ovalue = ASN1UTF8String(value);
          break;
      }

      if (ovalue == null) {
        throw ArgumentError('Could not process distinguished name field $name');
      }

      var pair = ASN1Sequence();
      pair.add(oid);
      pair.add(ovalue);

      var pairset = ASN1Set();
      pairset.add(pair);

      distinguishedName.add(pairset);
    });

    return distinguishedName;
  }

  ///
  /// Create  the public key ASN1Sequence for the csr.
  ///
  static ASN1Sequence _makePublicKeyBlock(RSAPublicKey publicKey) {
    var blockEncryptionType = ASN1Sequence();
    blockEncryptionType.add(ASN1ObjectIdentifier.fromName('rsaEncryption'));
    blockEncryptionType.add(ASN1Null());

    var publicKeySequence = ASN1Sequence();
    publicKeySequence.add(ASN1Integer(publicKey.modulus));
    publicKeySequence.add(ASN1Integer(publicKey.exponent));

    var blockPublicKey = ASN1BitString(publicKeySequence.encodedBytes);

    var outer = ASN1Sequence();
    outer.add(blockEncryptionType);
    outer.add(blockPublicKey);

    return outer;
  }

  ///
  /// Create  the public key ASN1Sequence for the ECC csr.
  ///
  static ASN1Sequence _makeEccPublicKeyBlock(ECPublicKey publicKey) {
    var algorithm = ASN1Sequence();
    algorithm.add(ASN1ObjectIdentifier.fromName('ecPublicKey'));
    algorithm
        .add(ASN1ObjectIdentifier.fromName(publicKey.parameters.domainName));

    var subjectPublicKey = ASN1BitString(publicKey.Q.getEncoded(false));

    var outer = ASN1Sequence();
    outer.add(algorithm);
    outer.add(subjectPublicKey);

    return outer;
  }

  ///
  /// Fetches a list of subject alternative names from the given [extData]
  ///
  static List<String> _fetchSansFromExtension(ASN1Object extData) {
    var sans = <String>[];
    var octet = extData as ASN1OctetString;
    var sanParser = ASN1Parser(octet.valueBytes());
    ASN1Sequence sanSeq = sanParser.nextObject();
    sanSeq.elements.forEach((ASN1Object san) {
      if (san.tag == 135) {
        var sb = StringBuffer();
        san.contentBytes().forEach((int b) {
          if (sb.isNotEmpty) {
            sb.write('.');
          }
          sb.write(b);
        });
        sans.add(sb.toString());
      } else {
        var s = String.fromCharCodes(san.contentBytes());
        sans.add(s);
      }
    });
    return sans;
  }

  ///
  /// Converts the bytes to a hex string
  ///
  static String _bytesAsString(Uint8List bytes) {
    var b = StringBuffer();
    bytes.forEach((v) {
      var s = v.toRadixString(16);
      if (s.length == 1) {
        b.write('0$s');
      } else {
        b.write(s);
      }
    });
    return b.toString().toUpperCase();
  }
}
