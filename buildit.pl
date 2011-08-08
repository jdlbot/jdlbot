#!perl


# Building with pp does NOT WORK with perl v5.10.0
#  v5.10.0 will produce strange behavior in PAR applications
#  Use Perl v5.10.1 and above only.

use File::Copy;
use File::Copy::Recursive qw(fcopy rcopy dircopy);
use Path::Class;
use File::Path qw(make_path remove_tree);
use File::Find;
use Cwd;

my $modulesToAdd = "-M Moose::Meta::Object::Trait -M Package::Stash::XS";
my $filesToAdd = "";

my $copyTo = (dir( cwd , 'build', 'current' ))->stringify;
my $copyFrom = (dir( cwd ))->stringify;
my $path_sep = '\/';

print "Copying source files into build/current\n\n";

find( { wanted => sub {
	if( $_ !~ /^\./ ){
		if( -f (file($copyFrom , $File::Find::name))->stringify ){
			my $toName = $File::Find::name;
			$toName =~ s/^src$path_sep//;
			print "$toName\n";
			rcopy( (file($copyFrom , $File::Find::name))->stringify , (file($copyTo , $toName))->stringify );
			$filesToAdd .= " -a $toName";
		}
	}
} , no_chdir => 0 }, 'src');

my $builddir = (dir('build', 'current'))->stringify;
if ( ! -d $builddir ){
	make_path($builddir);
}

if ( $^O =~ /MSWin/ ){
	print "\nWindows build.\n\n";
	
	copy((file('build', 'win', 'jdlbot.ico'))->stringify, (file($builddir, 'jdlbot.ico'))->stringify);
	
	chdir($builddir);
	my $result = `pp -M attributes -l LibXML $filesToAdd $modulesToAdd --icon jdlbot.ico -o jdlbotServer.exe jdlbotServer.pl`;
	
	print $result;
	if ( $? != 0 ){ die "Build failed.\n"; }
	
	chdir('..\..');
	my $distdir = 'dist';
	if ( ! -d $distdir ){
		make_path($distdir);
	}
	
	fcopy((file($builddir , 'jdlbotServer.exe'))->stringify, (file('dist', 'jdlbotServer.exe'))->stringify);
	`explorer dist`;
	print "Build successful.\n";
	
} elsif ( $^O eq 'darwin' ){
	print "\nMac OS X build.\n\n";
	
	chdir($builddir);
	my $libxml = '-l /usr/lib/libxml2.dylib';
	if( `which brew` ){
		my $brew_xml_dir = `brew --cellar libxml2`;
		$brew_xml_dir =~ s/\n|\r//g;
		if( -d "$brew_xml_dir" ){
			$brew_xml_dir = `brew --prefix libxml2`;
			$brew_xml_dir =~ s/\n|\r//g;
			$libxml = "-l $brew_xml_dir/lib/libxml2.dylib";
		}
	}
	
	my $result = `pp $libxml $filesToAdd $modulesToAdd -o jdlbotServer jdlbotServer.pl`;
	
	print $result;
	if ( $? != 0 ){ die "Build failed.\n"; }
	
	chdir('../..');
	my $distdir = 'dist';
	if ( ! -d $distdir ){
		make_path($distdir);
	}
	
	dircopy((dir('build', 'mac', 'jDlBot.app'))->stringify,(dir('dist', 'jDlBot.app'))->stringify );
	fcopy((file('build', 'current', 'jdlbotServer'))->stringify, (file('dist', 'jDlBot.app', 'Contents', 'Resources', 'jdlbotServer'))->stringify);
	`open dist`;
	print "Build successful.\n";
} else {
	print "Unsupported platform.  Try installing the required perl modules and running the script out of the src folder.\n" .
	"Maybe even send in a patch with a build script for your platform.\n";
}

print "Cleaning build folders.\n";
remove_tree($builddir, {keep_root => 1});

print "Done.\n";
exit(0);

