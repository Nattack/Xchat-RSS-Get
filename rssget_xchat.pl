#!/usr/bin/perl
#
# Xchat RSSget v0.2
# Description: 
#   RSSget is a simple RSS retriever that parses an XML script for several key tags
#   and outputs them to an Xchat query (RSSFeed).
#   I wrote this because I needed a reason to look at RSS feeds, and i never had the medium to do so.
#   I'm too lazy to open new programs, and the premade RSS scripts for xchat displayed in a manner i did not like.
#   Basically, if the news wasnt displayed infront of me, i wouldn't look at it. If the news would come to
#   a program i use regularly (Emacs, Xchat, aMSN) I would be more inclined to use it, and thus this script is born.
#use vars qw(%RSS %RSS_history $t_interval $max_item);
use LWP::Simple;
use 5.010;

Xchat::command("query -nofocus (RSSFeed)", "", "");
Xchat::hook_command("RSS", "get_rss");
Xchat::register( "RSSget", "0.2", "Grabs the newspaper for you at fixed intervals.", \&unload );

&get_rss(1);

#retrieve and process the RSS
sub get_rss {
    use vars qw(%RSS $t_interval $max_item);
    my ( 
    	$xml_data, 
    	$xml_item, 
    	@RSS_text, 
    	$firstelement, 
    	%RSS_history,
    	%RSS_tags,
    	$itemcount
    ) = undef;

#smart matching tools
    my ( %tag_id, @item, @title, @link, @description ) = undef;
    
    @item 		= qw/item entry/;
    @title 		= qw/title/;
    @link 		= qw/link/;
    @description 	= qw/description summary/;
    
#settings and history
    my $rssconf = $ENV{HOME} . "/.xchat2/RSSget.conf";
    my $history = $ENV{HOME} . "/.xchat2/.RSShistory";

#look for %RSS servers and $t_interval
    do $rssconf;
    %RSS_history = &hashload($history) unless $_[0]; #only load RSS history on second load.
    
    if ( ! %RSS ) {
        Xchat::print("No RSS found!", "(RSSFeed)", "");
    }
    
    foreach my $RSS_name (keys %RSS) {
    	@RSS_text = ();
        $xml_data = get( $RSS{lc($RSS_name)} );

	push(@RSS_text, "");
	push(@RSS_text, "\002\0034" . $RSS_name);
    # if get fails, do not attempt to parse the RSS, and proceed to the next server in line.
        unless ($xml_data) {
            Xchat::print ("Could not retrieve RSS: $RSS_name @ $RSS{$RSS_name}", "(RSSFeed)", "");
        } else {        
	#find tags
            $tag_id{"item"} = &smart_tag($xml_data, @item);
            $xml_item = &parse_tag($tag_id{"item"}, $xml_data);	
            $itemcount = 0;

	    $tag_id{"title"} = &smart_tag($xml_item, @title);
	    $tag_id{"link"} = &smart_tag($xml_item, @link);
	    #$tag_id{"description"} = &smart_tag($xml_item, @description);

        #get the first element of the list,	    
    	    $firstelement = &parse_tag($tag_id{"title"}, $xml_item);
	    
#	    push (@RSS_text, "");
#            push (@RSS_text, $RSS_name);

	#process the xml data so long as there is a title to be processed.
	    for ( my $i = 0 ; $i < $max_item ; $i++) {
	    
    		$xml_item = &parse_tag($tag_id{"item"}, $xml_data);

	    #check to see whether we've seen this before.
	        last if ( $RSS_history{$RSS_name} ~~ &parse_tag($tag_id{"title"}, $xml_item) );

		$RSS_tags{"title"} 		= &parse_tag($tag_id{"title"}, $xml_item);
		#$RSS_tags{"description"} 	= &parse_tag("description", $xml_item);
		if ( &parse_tag($tag_id{"link"}, $xml_item) ) {
		    $RSS_tags{"link"} 		= &parse_tag($tag_id{"link"}, $xml_item) 
		} else {
		    $RSS_tags{"link"} 		= &parse_tag_element($tag_id{"link"}, "href", $xml_item);
		}
		
	    #push a single element of data into the array, in this order, but only if the element exists.             
	        push( @RSS_text, "    \002" . $RSS_tags{"title"} ) if $RSS_tags{"title"};
    	        push( @RSS_text, "    --> " . $RSS_tags{"link"} ) if $RSS_tags{"link"};
	        #push( @RSS_text, "    ----> " . &strip_tags($RSS_tags{"description"}) ) if $RSS_tags{"description"};
		    
	    #remove data once we have read it, add item to count
	        $xml_data = &kill_tag($tag_id{"item"}, $xml_data);
	        $itemcount++;
	    }
	    
		
	#push first element of the list into the RSS_history hash after we have tested it
	    $RSS_history{$RSS_name} = $firstelement;	    
	    $xml_data = "";
	}
        &print_rss(@RSS_text) unless $itemcount == 0;

    }
    
    &hashwrite($history, %RSS_history);

    Xchat::hook_timer( $t_interval * 60 * 1000, "get_rss" );
    return Xchat::EAT_NONE;
}


# Parse a string for a tag, and return the string contained within
sub parse_tag {
    my ($tag, $data) = @_;
    $data =~ /<$tag.*?>(.*?)<\/$tag>/is; 
    return $1;
}

# Parse a string right out of a tag (tag element="data")
sub parse_tag_element {
    my ($tag, $element, $data) = @_;
    $data =~ /<$tag.*?$element="(.*?)".*?\/?>/is;
    return $1;
}

# Remove all tags from the text.
sub strip_tags {
    my ($text) = @_;
    $text =~ s/<\!\[.*?\[(.*?)\]\]>/$1/s;   
    $text =~ s/<.*?>//gs;
    return $text;
}

# Remove next tag and text from xml.
sub kill_tag {
    my ($tag, $data) = @_;
    $data =~ s/<$tag>.*?<\/$tag>//is;
    return $data;
}

# Print the RSS
sub print_rss {
    foreach my $text (@_) {
        Xchat::print (&strip_tags($text), "(RSSFeed)", "");
    }
}

# Automatically find the correct tag alias from a list of common tag aliases.
sub smart_tag {
    my ($data, @tag) = @_;
    foreach $curtag (@tag) {
    	return $curtag if $data =~ /<$curtag/i;
    }    
    return undef;
}

# Load a file into a hash, return a hash by reference
sub hashload {
    my ($file) = @_;
    my %hash;
    open (FILE, "<", $file);
    my @data = <FILE>;
    close FILE;    
    while (@data) {
    	chomp( $key = shift(@data) );
    	chomp( $val = shift(@data) );
        $hash{$key} = $val
    }   
    return %hash;
}

# Write hash to a file.
sub hashwrite {
    my ($file, %hash) = @_;    
    open (FILE, ">", $file);
    foreach my $key (keys %hash) {
        print FILE $key . "\n" . $hash{$key} . "\n";
    }    
    close *FILE;
}

sub unload {
    Xchat::print("###RSSget>Goodbye!","","");
}
