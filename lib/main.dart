import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'dart:convert';
import 'dart:io';
 
void main() {
  runApp(MyApp());
}
 
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Verkkosivuarvio',
      theme: CupertinoThemeData(
        primaryColor: CupertinoColors.systemBlue,
      ),
      home: WebAuditPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
 
class WebAuditPage extends StatefulWidget {
  @override
  _WebAuditPageState createState() => _WebAuditPageState();
}
 
class _WebAuditPageState extends State<WebAuditPage> {
  final TextEditingController _urlController = TextEditingController();
  String _result = '';
  String _robotsContent = '';
  String _hostLocation = '';
  bool _isLoading = false;
  bool _isRobotsVisible = false;
  String _loadTime = '';
  String _sslStatus = ''; // SSL status variable
  String _dkimStatus = ''; // DKIM status variable
  String _spfStatus = ''; // SPF status variable
  String _dnssecStatus = ''; // DNSSEC status variable
  String _securityHeaders = ''; // Security headers variable
 
  Future<void> _fetchWebsiteData() async {
    String url = _urlController.text.trim();
    if (!url.startsWith('https://')) {
      url = 'https://' + url.replaceFirst(RegExp(r'^http://'), '');
    }
 
    setState(() {
      _isLoading = true;
      _result = '';
      _robotsContent = '';
      _hostLocation = '';
      _isRobotsVisible = false;
      _loadTime = '';
      _sslStatus = '';
      _dkimStatus = '';
      _spfStatus = '';
      _dnssecStatus = '';
      _securityHeaders = '';
    });
 
    try {
      // SSL check
      try {
        final Uri uri = Uri.parse(url);
        final HttpClient client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => false;
        final HttpClientRequest request = await client.getUrl(uri);
        final HttpClientResponse response = await request.close();
 
        if (response.certificate != null) {
          _sslStatus = 'SSL/TLS-sertifikaatti on voimassa';
        } else {
          _sslStatus = 'SSL/TLS-sertifikaattia ei löytynyt';
        }
      } catch (e) {
        _sslStatus = 'SSL/TLS-sertifikaattia ei voitu tarkistaa: $e';
      }
 
      final headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3'
      };
 
      // Start time for load time calculation
      final startTime = DateTime.now();
      final response = await http.get(Uri.parse(url), headers: headers);
      final endTime = DateTime.now();
      final loadDuration = endTime.difference(startTime);
      _loadTime = 'Sivun latausaika: ${loadDuration.inMilliseconds} ms';
 
      if (response.statusCode == 200) {
        html_dom.Document document = html_parser.parse(response.body);
        final title =
            document.querySelector('title')?.text ?? 'Otsikkoa ei löytynyt';
        final metaDescription = document
                .querySelector('meta[name="description"]')
                ?.attributes['content'] ??
            'Kuvausta ei löytynyt';
        final keywords = document
                .querySelector('meta[name="keywords"]')
                ?.attributes['content'] ??
            'Avainsanoja ei löytynyt';
        final canonicalUrl = document.querySelector('link[rel="canonical"]')
                ?.attributes['href'] ?? 'Kanonista URL:ia ei löytynyt';
 
        String cms = 'CMS ei tunnistettu';
        if (response.body.contains('wp-content') ||
            response.headers.containsValue('WordPress')) {
          cms = 'WordPress';
        } else if (response.body.contains('<meta name="generator" content="Joomla!')) {
          cms = 'Joomla!';
        } else if (response.body.contains('Drupal')) {
          cms = 'Drupal';
        } else if (response.body.contains('Wix') ||
            document.querySelector('meta[content*="wix"]') != null) {
          cms = 'Wix';
        }
 
        String php = ' ei käytössä';
        if (response.headers['x-powered-by']?.contains('PHP') == true ||
            response.body.contains('Fatal error') ||
            response.body.contains('Warning:') ||
            response.body.contains('Parse error')) {
          php = ' käytössä';
        }
 
        final robotsResponse =
            await http.get(Uri.parse('$url/robots.txt'), headers: headers);
        final robotsTxt = robotsResponse.statusCode == 200
            ? robotsResponse.body
            : 'Robots.txt tiedostoa ei löytynyt';
 
        // Fetch host location
        final Uri uri = Uri.parse(url);
        final addresses = await InternetAddress.lookup(uri.host);
        if (addresses.isNotEmpty) {
          final ip = addresses.first.address;
          final geoResponse =
              await http.get(Uri.parse('http://ip-api.com/json/$ip'));
          if (geoResponse.statusCode == 200) {
            final locationData = jsonDecode(geoResponse.body);
            final country = locationData['country'] ?? 'Tuntematon maa';
            final city = locationData['city'] ?? 'Tuntematon kaupunki';
            _hostLocation = '$city, $country';
          } else {
            _hostLocation = 'Palvelimen sijaintia ei voitu määrittää';
          }
        }
 
        // DKIM Check
        _dkimStatus = await _checkDkim(uri.host);
 
        // SPF Check
        _spfStatus = await _checkSpf(uri.host);
 
        // DNSSEC Check
        _dnssecStatus = await _checkDnssec(uri.host);
 
        // HTTP Security Headers Check
        _securityHeaders = _checkSecurityHeaders(response.headers);
 
        setState(() {
          _result = 'Teknologiat ja CMS: $cms\n\n'
              'PHP: $php\n\n'
              'Otsikko: $title\n\n'
              'Kuvaus: $metaDescription\n\n'
              'Avainsanat: $keywords\n\n'
              'Kanoninen URL: $canonicalUrl\n\n'
              'Palvelimen sijainti: $_hostLocation\n\n'
              'Latausaika: $_loadTime\n\n'
              'DKIM Status: $_dkimStatus\n\n'
              'SPF Status: $_spfStatus\n\n'
              'DNSSEC Status: $_dnssecStatus\n\n'
              'HTTP Turvallisuusotsikot: $_securityHeaders\n\n';
          _robotsContent = robotsTxt;
        });
      } else {
        setState(() {
          _result =
              'Virhe: Ei voitu hakea tietoja. Statuskoodi: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _result = 'Virhe: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
 
  Future<String> _checkDkim(String domain) async {
    try {
      String selector = 'default';
      final dkimRecord =
          await http.get(Uri.parse('https://dns.google/resolve?name=$selector._domainkey.$domain&type=TXT'));
 
      if (dkimRecord.statusCode == 200) {
        final jsonResponse = jsonDecode(dkimRecord.body);
        final records = jsonResponse['Answer'] as List<dynamic>?;
 
        if (records != null && records.isNotEmpty) {
          return 'DKIM-tietue löytyi: ${records.map((r) => r['data']).join(", ")}';
        } else {
          return 'DKIM-tietuetta ei löytynyt';
        }
      } else {
        return 'Virhe DKIM-tietueen haussa: ${dkimRecord.statusCode}';
      }
    } catch (e) {
      return 'Virhe tarkistuksessa: $e';
    }
  }
 
  Future<String> _checkSpf(String domain) async {
    try {
      final spfRecord =
          await http.get(Uri.parse('https://dns.google/resolve?name=$domain&type=TXT'));
 
      if (spfRecord.statusCode == 200) {
        final jsonResponse = jsonDecode(spfRecord.body);
        final records = jsonResponse['Answer'] as List<dynamic>?;
 
        if (records != null && records.isNotEmpty) {
          for (var record in records) {
            final data = record['data'] as String;
            if (data.contains('v=spf1')) {
              return 'SPF-tietue löytyi: $data';
            }
          }
          return 'SPF-tietuetta ei löytynyt';
        } else {
          return 'SPF-tietuetta ei löytynyt';
        }
      } else {
        return 'Virhe SPF-tietueen haussa: ${spfRecord.statusCode}';
      }
    } catch (e) {
      return 'Virhe tarkistuksessa: $e';
    }
  }
 
  Future<String> _checkDnssec(String domain) async {
    try {
      // DNSSEC check using Google Public DNS API
      final dnssecRecord =
          await http.get(Uri.parse('https://dns.google/resolve?name=$domain&type=DNSKEY'));
 
      if (dnssecRecord.statusCode == 200) {
        final jsonResponse = jsonDecode(dnssecRecord.body);
        final records = jsonResponse['Answer'] as List<dynamic>?;
 
        if (records != null && records.isNotEmpty) {
          return 'DNSSEC on käytössä: ${records.map((r) => r['data']).join(", ")}';
        } else {
          return 'DNSSEC ei ole käytössä';
        }
      } else {
        return 'Virhe DNSSEC-tietueen haussa: ${dnssecRecord.statusCode}';
      }
    } catch (e) {
      return 'Virhe DNSSEC-tarkistuksessa: $e';
    }
  }
 
  String _checkSecurityHeaders(Map<String, String> headers) {
    List<String> headersList = [];
 
    if (headers.containsKey('Content-Security-Policy')) {
      headersList.add('Content-Security-Policy: ${headers['Content-Security-Policy']}');
    } else {
      headersList.add('Content-Security-Policy: Ei löytynyt');
    }
 
    if (headers.containsKey('X-Content-Type-Options')) {
      headersList.add('X-Content-Type-Options: ${headers['X-Content-Type-Options']}');
    } else {
      headersList.add('X-Content-Type-Options: Ei löytynyt');
    }
 
    if (headers.containsKey('X-Frame-Options')) {
      headersList.add('X-Frame-Options: ${headers['X-Frame-Options']}');
    } else {
      headersList.add('X-Frame-Options: Ei löytynyt');
    }
 
    if (headers.containsKey('Strict-Transport-Security')) {
      headersList.add('Strict-Transport-Security: ${headers['Strict-Transport-Security']}');
    } else {
      headersList.add('Strict-Transport-Security: Ei löytynyt');
    }
 
    return headersList.join('\n');
  }
 
  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('Verkkosivuarvio'),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              CupertinoTextField(
                controller: _urlController,
                placeholder: 'Syötä URL',
                padding: EdgeInsets.all(12),
                onSubmitted: (value) => _fetchWebsiteData(),
              ),
              SizedBox(height: 16),
              CupertinoButton(
                child: Text('Tarkista'),
                color: CupertinoColors.activeBlue,
                onPressed: _isLoading ? null : _fetchWebsiteData,
              ),
              SizedBox(height: 16),
              if (_isLoading)
                CupertinoActivityIndicator()
              else if (_result.isNotEmpty)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_sslStatus.isNotEmpty) ...[
                          _buildInfoTile('SSL Status', _sslStatus),
                        ],
                        if (_dkimStatus.isNotEmpty) ...[
                          _buildInfoTile('DKIM (DomainKeys Identified Mail)', _dkimStatus),
                        ],
                        if (_spfStatus.isNotEmpty) ...[
                          _buildInfoTile('SPF (Sender Policy Framework)', _spfStatus),
                        ],
                        if (_dnssecStatus.isNotEmpty) ...[
                          _buildInfoTile('DNSSEC', _dnssecStatus),
                        ],
                        if (_loadTime.isNotEmpty) ...[
                          _buildInfoTile('Latausaika', _loadTime),
                        ],
                        if (_result.isNotEmpty) ...[
                          _buildInfoTile('Tulokset', _result),
                        ],
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isRobotsVisible = !_isRobotsVisible;
                            });
                          },
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemGrey6,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: CupertinoColors.systemGrey4,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Avaa robots.txt',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Icon(
                                  _isRobotsVisible
                                      ? CupertinoIcons.chevron_up
                                      : CupertinoIcons.chevron_down,
                                  color: CupertinoColors.systemGrey,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_isRobotsVisible) ...[
                          Container(
                            margin: EdgeInsets.only(top: 8),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemGrey5,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              _robotsContent,
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
 
  Widget _buildInfoTile(String title, String content) {
    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(content),
          ],
        ),
      ),
    );
  }
}