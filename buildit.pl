#!perl


# Building with pp does NOT WORK with perl v5.10.0
#  v5.10.0 will produce strange behavior in PAR applications

use File::Copy;
use File::Copy::Recursive qw(fcopy rcopy dircopy);
use Path::Class;
use File::Path qw(make_path remove_tree);

opendir(SRC, 'src');
my @srcfiles = readdir(SRC);
closedir(SRC);

my @filelist = ();
while (@srcfiles){
	my $file = pop(@srcfiles);
	
	if ( $file !~ /^\./ ){
		push(@filelist, $file);
	}
}

my $builddir = (dir('build', 'current'))->stringify;
if ( ! -d $builddir ){
	make_path($builddir);
}

print "\nCopying files to build folder.\n\n";
my $filesToAdd = "";
foreach my $file (@filelist){
	my $src = (file('src', $file))->stringify;
	my $dest = (file('build', 'current', $file))->stringify;
	print "$src, $dest\n";
	$filesToAdd .= "-a " . $file . " ";
	copy($src, $dest);
}

if ( $^O =~ /MSWin/ ){
	print "\nWindows build.\n\n";
	
	copy((file('build', 'win', 'build.pl'))->stringify, (file('build', 'current', 'build.pl'))->stringify);
	copy((file('build', 'win', 'jdlbot.ico'))->stringify, (file('build', 'current', 'jdlbot.ico'))->stringify);
	
	chdir((dir('build', 'current'))->stringify);
	my $result = `pp -M attributes -l LibXML $filesToAdd --icon jdlbot.ico -o jdlbotServer.exe jdlbotServer.pl`;
	
	print $result;
	if ( $? != 0 ){ die "Build failed.\n"; }
	
	chdir('..\..');
	my $distdir = 'dist';
	if ( ! -d $distdir ){
		make_path($distdir);
	}
	
	fcopy((file('build', 'current', 'jdlbotServer.exe'))->stringify, (file('dist', 'jdlbotServer.exe'))->stringify);
	`explorer dist`;
	print "Build successful.\n";
	
} elsif ( $^O eq 'darwin' ){
	print "\nMac OS X build.\n\n";
	
	copy((file('build', 'mac', 'build.pl'))->stringify, (file('build', 'current', 'build.pl'))->stringify);
	
	chdir((dir('build', 'current'))->stringify);
	my $result = `pp -l libxml2 $filesToAdd -o jdlbotServer jdlbotServer.pl`;
	
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
remove_tree((dir('build', 'current'))->stringify, {keep_root => 1});

print "Done.\n";
exit(0);