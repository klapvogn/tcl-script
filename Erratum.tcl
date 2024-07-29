 ###############################################################################
#
# Erratum
# v1.02 (16/04/2020)   �2016-2020 Menz Agitat
#
# IRC: irc.epiknet.org  #boulets / #eggdrop
#
# Mes scripts sont t�l�chargeables sur http://www.eggdrop.fr
# Retrouvez aussi toute l'actualit� de mes releases sur
# http://www.boulets.oqp.me/tcl/scripts/index.html
#
 ###############################################################################

#
# Description
#
# Erratum permet de corriger ce qui a �t� dit auparavant sur un chan.
# L'objectif peut �tre de corriger les fautes d'orthographe faites par d'autres,
# ou encore de leur faire dire autre chose que ce qu'ils avaient voulu dire.
#
 ###############################################################################

#
# Licence
#
#		Cette cr�ation est mise � disposition selon le Contrat
#		Attribution-NonCommercial-ShareAlike 3.0 Unported disponible en ligne
#		http://creativecommons.org/licenses/by-nc-sa/3.0/ ou par courrier postal �
#		Creative Commons, 171 Second Street, Suite 300, San Francisco, California
#		94105, USA.
#		Vous pouvez �galement consulter la version fran�aise ici :
#		http://creativecommons.org/licenses/by-nc-sa/3.0/deed.fr
#
 ###############################################################################

if {[::tcl::info::commands ::erratum::unload] eq "::erratum::unload"} { ::erratum::unload }
if { [package vcompare [lindex [split $::version] 0] 1.6.20] == -1 } { putloglev o * "\00304\[Erratum - erreur\]\003 La version de votre Eggdrop est\00304 ${::version}\003; Erratum ne fonctionnera correctement que sur les Eggdrops version 1.6.20 ou sup�rieure." ; return }
if { [::tcl::info::tclversion] < 8.5 } { putloglev o * "\00304\[Erratum - erreur\]\003 Erratum n�cessite que Tcl 8.5 (ou plus) soit install� pour fonctionner. Votre version actuelle de Tcl est\00304 ${::tcl_version}\003." ; return }
if { [catch { package require msgcat }] } { putloglev o * "\00304\[Erratum - erreur\]\003 Erratum n�cessite le package msgcat pour fonctionner. Le chargement du script a �t� annul�." ; return }
package require Tcl 8.5
namespace eval ::erratum {



 ###############################################################################
### Configuration
 ###############################################################################


	# Emplacement et nom du fichier de configuration.
	variable config_file "scripts/oldboys/erratum/erratum.cfg"
	
	#####  LANGUE  ###############################################################

	# Langue des messages du script ( fr = fran�ais / en = english )
	# Remarque : Il s'agit d'un r�glage global de votre Eggdrop; ce param�tre est
	#	mis ici pour vous en faciliter l'acc�s mais vous devez veiller � ce qu'il
	# soit r�gl� de la m�me mani�re partout.
	# Concr�tement, vous ne pouvez pas d�finir la langue d'un script sur "fr" et
	# celle d'un autre sur "en".
	::msgcat::mclocale "en"

	# Emplacement du catalogue de messages.
	variable language_files_directory "scripts/oldboys/erratum/language"



 ###############################################################################
### Fin de la configuration
 ###############################################################################



	 #############################################################################
	### Initialisation
	 #############################################################################
	variable scriptname "Erratum"
	variable version "1.02.20200416"
	setudef flag erratum
	variable memory {}
	variable memory_lock 0
	# Chargement du catalogue de messages.
	::msgcat::mcload [file join $::erratum::language_files_directory]
	# Lecture de la configuration.
	if { [file exists $::erratum::config_file] } {
		eval [list source $::erratum::config_file]
	} else {
		# Message : "\00304\[%s - erreur\]\003 Le fichier de configuration n'a pas �t� trouv� � l'emplacement indiqu� ( %s ). Le chargement du script est annul�."
		putloglev o * [::msgcat::mc m1 $::erratum::scriptname $::erratum::config_file]
		namespace delete ::erratum
		return
	}
	proc unload {args} {
		# Message : "D�sallocation des ressources de %s..."
		putlog [::msgcat::mc m0 $::erratum::scriptname]
		foreach binding [lsearch -inline -all -regexp [binds *[set ns [::tcl::string::range [namespace current] 2 end]]*] " \{?(::)?$ns"] {
			unbind [lindex $binding 0] [lindex $binding 1] [lindex $binding 2] [lindex $binding 4]
		}
		foreach running_utimer [utimers] {
			if { [::tcl::string::match "*[namespace current]::*" [lindex $running_utimer 1]] } { killutimer [lindex $running_utimer 2] }
		}
		::msgcat::mcforgetpackage
		namespace delete ::erratum
	}
}

 ###############################################################################
### !erratum <mot/remplacement[/mot/remplacement[/...]]>
### Un utilisateur demande une correction.
 ###############################################################################
proc ::erratum::process {nick host hand chan arg} {
	if {
		(![channel get $chan erratum])
		|| (($::erratum::antiflood == 1)
		&& (([::erratum::antiflood $nick $chan "nick" $::erratum::erratum_cmd $::erratum::flood_erratum_cmd])
		|| ([::erratum::antiflood $nick $chan "chan" "*" $::erratum::flood_global])))
	} then {
		return
	} else {
		if { $::erratum::preferred_display_mode == 1 } {
			set output_method "PRIVMSG"
			set output_target $chan
		} else {
			set output_method "NOTICE"
			set output_target $nick
		}
		if {
			([::tcl::string::map {"/" ""} $arg] eq "")
			|| ![::tcl::string::match "*/*" $arg]
		} then {
			# Message : "\037Syntaxe\037 : \002%s\002 \00314<\003mot/remplacement\00314\[\003/mot/remplacement\00314\[\003/...\00314\]\]>\003 \00307|\003 Remplace toutes les occurrences de \"mot\" par \"remplacement\" dans une ligne r�cemment �crite."
			::erratum::display_output help $output_method $output_target [::msgcat::mc m3 $::erratum::erratum_cmd]
		} elseif { ![::tcl::dict::exists $::erratum::memory $chan] } {
			# Message : "\037Erreur\037 : Aucune correspondance n'a �t� trouv�e."
			::erratum::display_output help $output_method $output_target [::msgcat::mc m4]
		} else {
			# On substitue les / qui ont �t� antislash�s afin de ne pas les confondre
			# avec les s�parateurs.
			set arg [::tcl::string::map {"\\/" "@%slash%@"} $arg]
			# On interdit l'utilisation d'un nombre pair de "/"
			if { ![expr {[llength [regexp -all -inline {/} $arg]] % 2}] } {
				# Message : "\037Erreur\037 : Les s�parateurs doivent �tre en nombre impair."
				::erratum::display_output help $output_method $output_target [::msgcat::mc m5]
				return
			} else {
				set arg [split $arg "/"]
				set match_found 0
				set reversed_memory_index 0
				foreach memorized_line [lreverse [::tcl::dict::get $::erratum::memory $chan]] {
					foreach {word replacement} $arg {
						# On emp�che le remplacement de strings vides.
						if { $word eq "" } {
							# Message : "\037Erreur\037 : Le mot � remplacer ne peut �tre une cha�ne de caract�res vide."
							::erratum::display_output help $output_method $output_target [::msgcat::mc m6]
							return
						} else {
							set word [::tcl::string::map {"@%slash%@" "/"} $word]
							set replacement [::tcl::string::map {"@%slash%@" "/"} $replacement]
							# Remarque : on utilise un symbole qui sera substitu� par \002 �
							# l'affichage et supprim� lors de la mise � jour de la phrase
							# m�moris�e.
							if { [::tcl::string::is digit [set regexpable_word [regsub -all {\W} $word {\\&}]]] } {
								# Remarque : le [^\003] dans l'expression r�guli�re sert � �viter
								# le remplacement d'�l�ments faisant partie de la couleur du texte.
								# Remarque : les \177 ins�r�s au milieu de la cha�ne de
								# remplacement permet d'�viter que le mot remplac� soit match�
								# une nouvelle fois dans le cas d'un remplacement inverse.
								set regular_expression "(\[^\\003\])$regexpable_word"
								set replacement_string "\\1\177[::tcl::string::range $replacement 0 0]\177\177[::tcl::string::range $replacement 1 end]\177"
							} else {
								set regular_expression $regexpable_word
								set replacement_string "\177[::tcl::string::range $replacement 0 0]\177\177[::tcl::string::range $replacement 1 end]\177"
							}
							if { [regsub -all -nocase $regular_expression $memorized_line $replacement_string memorized_line] } {
								set match_found 1
							}
						}
					}
					# Si une correspondance a �t� trouv�e et qu'un remplacement a �t�
					# effectu�, on corrige la ligne m�moris�e.
					if { $match_found } {
						set memory_index [expr {[llength [::tcl::dict::get $::erratum::memory $chan]] - ($reversed_memory_index + 1)}]
						::tcl::dict::set ::erratum::memory $chan [lreplace [::tcl::dict::get $::erratum::memory $chan] $memory_index $memory_index [::tcl::string::map {"\177" ""} $memorized_line]]
						break
					}
					incr reversed_memory_index
				}					
				if { $match_found } {
					# On verrouille la m�morisation de ce que l'Eggdrop dit afin d'emp�cher
					# qu'il m�morise la ligne de correction.
					set ::erratum::memory_lock 1
					::erratum::display_output help PRIVMSG $chan "$nick ${::erratum::prefix}[::tcl::string::map {"\177\177" "" "\177" "\002"} $memorized_line]"
				} else {
					# Message : "\037Erreur\037 : Aucune correspondance n'a �t� trouv�e."
					::erratum::display_output help $output_method $output_target [::msgcat::mc m4]
				}
			}
		}
	}
	return
}

 ###############################################################################
### M�morisation du texte des utilisateurs
 ###############################################################################
proc ::erratum::user_msg_listen {nick host hand chan text} {
	if {!([channel get $chan erratum])} then {
      return
   } elseif {([::tcl::string::match -nocase "$::erratum::erratum_cmd*" $text])} {
		#::erratum::process $nick $host $hand $chan [string range $text [string length $::erratum::erratum_cmd] end]
		::erratum::process $nick $host $hand $chan [string trimleft [string range $text [string length $::erratum::erratum_cmd] end]]
	} else {
		::tcl::dict::lappend ::erratum::memory $chan "$text"
		if { [llength [::tcl::dict::get $::erratum::memory $chan]] > $::erratum::max_memory } {
			::tcl::dict::set ::erratum::memory $chan [lreplace [::tcl::dict::get $::erratum::memory $chan] 0 0]
		}
	}
}

 ###############################################################################
### M�morisation des CTCP ACTION des utilisateurs
 ###############################################################################
proc ::erratum::user_CTCP_ACTION_listen {nick host hand chan command text} {
	if {
		([::tcl::string::first "#" $chan] != 0)
		|| !([channel get $chan erratum])
	} then {
		return
	} else {
		::tcl::dict::lappend ::erratum::memory $chan "* $nick $text"
		if { [llength [::tcl::dict::get $::erratum::memory $chan]] > $::erratum::max_memory } {
			::tcl::dict::set ::erratum::memory $chan [lreplace [::tcl::dict::get $::erratum::memory $chan] 0 0]
		}
	}
}

 ###############################################################################
### M�morisation du texte + CTCP ACTION de l'Eggdrop
 ###############################################################################
proc ::erratum::eggdrop_listen {queue data status} {
	lassign [set data [split $data]] msg_mode chan
	if {
		([::tcl::string::first "#" $chan] != 0)
		|| !([validchan $chan])
		|| !([channel get $chan erratum])
		|| ($msg_mode ne "PRIVMSG")
	} then {
		return
	} elseif { $::erratum::memory_lock } {
		set ::erratum::memory_lock 0
		return
	} else {
		set text [::tcl::string::range [join [lrange $data 2 end]] 1 end]
		# Gestion des CTCP ACTION (/me)
		if { ![::tcl::string::first "\001ACTION" $text] } {
			::tcl::dict::lappend ::erratum::memory $chan "* $::nick [::tcl::string::map { "\001ACTION" "" "\001" ""} $text]"
		} else {
			::tcl::dict::lappend ::erratum::memory $chan "$::nick $text"
		}
		if { [llength [::tcl::dict::get $::erratum::memory $chan]] > $::erratum::max_memory } {
			::tcl::dict::set ::erratum::memory $chan [lreplace [::tcl::dict::get $::erratum::memory $chan] 0 0]
		}
	}
}

 ###############################################################################
### Affichage d'un texte, filtrage des styles si n�cessaire.
### * queue peut valoir help, quick, now, serv, dcc, log ou loglev
### * method peut valoir PRIVMSG ou NOTICE et sera ignor� si queue vaut dcc ou
###      loglev
### * target peut �tre un nick, un chan ou un idx, et sera ignor� si queue vaut
###      loglev
 ###############################################################################
proc ::erratum::display_output {queue method target text} {
	if {
		($::erratum::monochrome)
		|| (!([::tcl::string::first "#" $target])
		&& ([::tcl::string::match *c* [lindex [split [getchanmode $target]] 0]]))
		|| (($queue eq "dcc")
		&& (![matchattr [idx2hand $target] h]))
	} then {
		# Remarque : l'aller-retour d'encodage permet de contourner un bug d'Eggdrop
		# qui corromp le charset dans certaines conditions lors de l'utilisation de
		# regsub sur une cha�ne de caract�res.
		regsub -all "\017" [stripcodes abcgru $text] "" text
	}
	switch -- $queue {
		help - quick - now - serv {
			put$queue "$method $target :$text"
		}
		dcc {
			putdcc $target $text
		}
		loglev {
			putloglev o * $text
		}
		log {
			putlog $text
		}
	}
}

 ###############################################################################
### Contr�le du flood.
### - focus peut valoir "chan" ou "nick" et diff�renciera un contr�le de flood
###		collectif o� les commandes seront bloqu�es pour tout le monde, d'un
###		contr�le individuel o� les commandes seront bloqu�es pour un seul individu.
### - command peut valoir "*" ou le nom d'une commande et diff�renciera un
###		contr�le par commande ou toutes commandes du script confondues.
### - limit est exprim� sous la forme "xx:yy", o� xx = nombre maximum de
###		requ�tes et yy = dur�e d'une instance.
 ###############################################################################
proc ::erratum::antiflood {nick chan focus command limit} {
	lassign [split $limit ":"] max_instances instance_length
	if { $focus eq "chan" } {
		set hash [md5 "$chan,$command"]
	} else {
		set hash [md5 "$nick,$chan,$command"]
	}
	# L'antiflood est dans un statut neutre, on l'initialise.
	if { ![::tcl::info::exists ::erratum::instance($hash)] } {
		set ::erratum::instance($hash) 0
		set ::erratum::antiflood_msg($hash) 0
	}
	if { $::erratum::instance($hash) >= $max_instances } {
		if { $::erratum::preferred_display_mode == 1 } {
			set output_method "PRIVMSG"
			set output_target $chan
		} else {
			set output_method "NOTICE"
			set output_target $nick
		}
		if { !$::erratum::antiflood_msg($hash) } {
			set ::erratum::antiflood_msg($hash) 2
			if { $command eq "*" } {
				if { $focus eq "chan" } {
					# Message : "\00304:::\003 \00314Contr�le de flood activ� pour toutes les commandes du script %s : pas plus de %s %s toutes les %s %s.\003"
					# Textes : "requ�te" "requ�tes" "seconde" "secondes"
					::erratum::display_output help PRIVMSG $chan [::msgcat::mc m7 $::erratum::scriptname $max_instances [::erratum::plural $max_instances [::msgcat::mc m8] [::msgcat::mc m9]] $instance_length [::erratum::plural $instance_length [::msgcat::mc m10] [::msgcat::mc m11]]]
				} else {
					# Message : "\00304:::\003 \00314Contr�le de flood activ� pour %s sur toutes les commandes du script %s : pas plus de %s %s toutes les %s %s.\003"
					# Textes : "requ�te" "requ�tes" "seconde" "secondes"
					::erratum::display_output help PRIVMSG $chan [::msgcat::mc m12 $nick $::erratum::scriptname $max_instances [::erratum::plural $max_instances [::msgcat::mc m8] [::msgcat::mc m9]] $instance_length [::erratum::plural $instance_length [::msgcat::mc m10] [::msgcat::mc m11]]]
				}
			} else {
				if { $focus eq "chan" } {
					# Message : "\00304:::\003 \00314Contr�le de flood activ� pour la commande \"%s\" : pas plus de %s %s toutes les %s %s.\003"
					# Textes : "requ�te" "requ�tes" "seconde" "secondes"
					::erratum::display_output help $output_method $output_target [::msgcat::mc m13 $command $max_instances [::erratum::plural $max_instances [::msgcat::mc m8] [::msgcat::mc m9]] $instance_length [::erratum::plural $instance_length [::msgcat::mc m10] [::msgcat::mc m11]]]
				} else {
					# Message : "\00304:::\003 \00314Contr�le de flood activ� pour %s sur la commande \"%s\" : pas plus de %s %s toutes les %s %s.\003"
					# Textes : "requ�te" "requ�tes" "seconde" "secondes"
					::erratum::display_output help $output_method $output_target [::msgcat::mc m14 $nick $command $max_instances [::erratum::plural $max_instances [::msgcat::mc m8] [::msgcat::mc m9]] $instance_length [::erratum::plural $instance_length [::msgcat::mc m10] [::msgcat::mc m11]]]
				}
			}
			if { [set msgresettimer [::erratum::utimerexists "::erratum::antiflood_msg_reset $hash"]] ne ""} {
				killutimer $msgresettimer
			}
			utimer $::erratum::antiflood_msg_interval [list ::erratum::antiflood_msg_reset $hash]
		} elseif { $::erratum::antiflood_msg($hash) == 1 } {
			set ::erratum::antiflood_msg($hash) 2
			if { $command eq "*" } {
				# Message : "\00304:::\003 \00314Le contr�le de flood est toujours actif, merci de patienter.\003"
				::erratum::display_output help PRIVMSG $chan [::msgcat::mc m15]
			} else {
				# Message : "\00304:::\003 \00314Le contr�le de flood est toujours actif, merci de patienter.\003"
				::erratum::display_output help $output_method $output_target [::msgcat::mc m15]
			}
			if { [set msgresettimer [::erratum::utimerexists "::erratum::antiflood_msg_reset $hash"]] ne ""} {
				killutimer $msgresettimer
			}
			utimer $::erratum::antiflood_msg_interval [list ::erratum::antiflood_msg_reset $hash]
		}
		return "1"
	} else {
		incr ::erratum::instance($hash) 1
		utimer $instance_length [list ::erratum::antiflood_close_instance $hash]
		return "0"
	}
}
proc ::erratum::antiflood_close_instance {hash} {
	incr ::erratum::instance($hash) -1
	# si le nombre d'instances retombe � 0, on efface les variables instance et
	# antiflood_msg afin de ne pas encombrer la m�moire inutilement
	if { $::erratum::instance($hash) == 0 } {
		unset ::erratum::instance($hash)
		unset ::erratum::antiflood_msg($hash)
	# le nombre d'instances est retomb� en dessous du seuil critique, on
	# r�initialise antiflood_msg
	} else {
		set ::erratum::antiflood_msg($hash) 0
		if { [set msgresettimer [::erratum::utimerexists "::erratum::antiflood_msg_reset $hash"]] ne ""} {
			killutimer $msgresettimer
		}
	}
	return
}
proc ::erratum::antiflood_msg_reset {hash} {
	set ::erratum::antiflood_msg($hash) 1
	return
}

 ###############################################################################
### Accorde au singulier ou au pluriel.
 ###############################################################################
proc ::erratum::plural {value singular plural} {
	if {
		($value >= 2)
		|| ($value <= -2)
	} then {
		return $plural
	} else {
		return $singular
	}
}

 ###############################################################################
### Test de l'existence d'un utimer, renvoi de son ID
 ###############################################################################
proc ::erratum::utimerexists {command} {
	foreach utimer_ [utimers] {
		if { ![::tcl::string::compare $command [lindex $utimer_ 1]] } {
			return [lindex $utimer_ 2]
		}
	}
}

 ###############################################################################
### Binds
 ###############################################################################
bind evnt - prerehash ::erratum::unload
#bind pub $::erratum::erratum_auth $::erratum::erratum_cmd ::erratum::process
bind pubm - * ::erratum::user_msg_listen
bind CTCP -|- ACTION ::erratum::user_CTCP_ACTION_listen
bind out - "% sent" ::erratum::eggdrop_listen


#	Message : "%s v%s (�2016-2020 Menz Agitat) a �t� charg�."
namespace eval ::erratum {
	putlog [::msgcat::mc m2 $::erratum::scriptname $::erratum::version]
}
